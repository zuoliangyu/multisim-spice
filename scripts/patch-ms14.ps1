# Copy the .model parameters of a SPICE netlist into a Multisim 14 design (.ms14) that was created
# by importing that netlist. Multisim's netlist import replaces every D/Q/M/J device with a virtual
# part that has default parameters; this restores the netlist's models so schematic and simulation match.
#
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File patch-ms14.ps1 <netlist.cir> <imported.ms14> [<out.ms14>]
#   <out.ms14> defaults to <imported>_models.ms14. The output is written as plain XML, which Multisim 14 opens directly.
# Every patched device is read back and checked. Exit 0 on success; on any mismatch nothing is written and exit is 1.

param(
  [Parameter(Mandatory = $true)][string]$Netlist,
  [Parameter(Mandatory = $true)][string]$Design,
  [string]$Out = ""
)

Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Text;
using System.Text.RegularExpressions;

public static class Ms14 {
  // ---- PKWARE DCL "explode" (port of zlib contrib/blast.c); .ms14 payloads use this format ----
  const int MAXBITS = 13;
  static readonly byte[] LITLEN = {11,124,8,7,28,7,188,13,76,4,10,8,12,10,12,10,8,23,8,9,7,6,7,8,7,6,55,8,23,24,12,11,7,9,11,12,6,7,22,5,
    7,24,6,11,9,6,7,22,7,11,38,7,9,8,25,11,8,11,9,12,8,12,5,38,5,38,5,11,7,5,6,21,6,10,53,8,7,24,10,27,
    44,253,253,253,252,252,252,13,12,45,12,45,12,61,12,45,44,173};
  static readonly byte[] LENLEN = {2,35,36,53,38,23};
  static readonly byte[] DISTLEN = {2,20,53,230,247,151,248};
  static readonly int[] BASE = {3,2,4,5,6,7,8,9,10,12,16,24,40,72,136,264};
  static readonly int[] EXTRA = {0,0,0,0,0,0,0,0,1,2,3,4,5,6,7,8};

  class Huff { public int[] Count = new int[MAXBITS + 1]; public int[] Symbol; }
  static Huff Construct(byte[] rep) {
    var length = new List<int>();
    foreach (byte b in rep) for (int k = 0; k <= (b >> 4); k++) length.Add(b & 15);
    var h = new Huff(); h.Symbol = new int[length.Count];
    foreach (int l in length) h.Count[l]++;
    var offs = new int[MAXBITS + 2];
    for (int l = 1; l < MAXBITS; l++) offs[l + 1] = offs[l] + h.Count[l];
    for (int s = 0; s < length.Count; s++) if (length[s] != 0) h.Symbol[offs[length[s]]++] = s;
    return h;
  }
  class Bits {
    byte[] d; int p, buf, cnt;
    public Bits(byte[] data, int start) { d = data; p = start; }
    public int Bit() {
      if (cnt == 0) { if (p >= d.Length) throw new Exception("truncated .ms14 payload"); buf = d[p++]; cnt = 8; }
      int b = buf & 1; buf >>= 1; cnt--; return b;
    }
    public int Get(int n) { int v = 0; for (int i = 0; i < n; i++) v |= Bit() << i; return v; }
  }
  static int Decode(Bits br, Huff h) {
    int code = 0, first = 0, index = 0;
    for (int l = 1; l <= MAXBITS; l++) {
      code |= br.Bit() ^ 1;
      int c = h.Count[l];
      if (code < first + c) return h.Symbol[index + code - first];
      index += c; first += c; first <<= 1; code <<= 1;
    }
    throw new Exception("bad Huffman code in .ms14 payload");
  }
  static byte[] Explode(byte[] data, int start) {
    int lit = data[start], dict = data[start + 1];
    if (lit > 1 || dict < 4 || dict > 6) throw new Exception("unknown .ms14 compression header");
    Huff litc = Construct(LITLEN), lenc = Construct(LENLEN), distc = Construct(DISTLEN);
    var br = new Bits(data, start + 2); var o = new List<byte>(1 << 20);
    while (true) {
      if (br.Bit() == 1) {
        int sym = Decode(br, lenc), len = BASE[sym] + br.Get(EXTRA[sym]);
        if (len == 519) break;
        int s = len == 2 ? 2 : dict;
        int dist = (Decode(br, distc) << s) + br.Get(s) + 1;
        for (int k = 0; k < len; k++) o.Add(o[o.Count - dist]);
      } else o.Add((byte)(lit == 1 ? Decode(br, litc) : br.Get(8)));
    }
    return o.ToArray();
  }

  // .ms14 is either plain XML, or "MSMCompressedElectronicsWorkbenchXML" + uint32 total size + uint32 0,
  // followed by chunks of (uint32 chunk size, uint32 compressed size, DCL payload), at most 900000 bytes each
  public static string ReadDesign(byte[] raw) {
    string magic = "MSMCompressedElectronicsWorkbenchXML";
    if (raw.Length > 52 && Encoding.ASCII.GetString(raw, 0, magic.Length) == magic) {
      int total = BitConverter.ToInt32(raw, 36), pos = 44;
      var xml = new List<byte>(total);
      while (xml.Count < total) {
        if (pos + 8 > raw.Length) throw new Exception("truncated .ms14 chunk header");
        int usize = BitConverter.ToInt32(raw, pos), csize = BitConverter.ToInt32(raw, pos + 4);
        byte[] chunk = Explode(raw, pos + 8);
        if (chunk.Length != usize) throw new Exception("decompressed chunk size mismatch");
        xml.AddRange(chunk); pos += 8 + csize;
      }
      if (xml.Count != total) throw new Exception("decompressed size mismatch");
      return Encoding.ASCII.GetString(xml.ToArray());
    }
    string text = Encoding.ASCII.GetString(raw);
    if (!text.StartsWith("<?xml")) throw new Exception("not a Multisim 14 design file");
    return text;
  }

  // ---- netlist: element name -> model name, model name -> "TYPE(params)" ----
  public static void ParseNetlist(string text, Dictionary<string, string> elementModel, Dictionary<string, string> models,
                                  Dictionary<string, string[]> elementNodes) {
    var lines = new List<string>();
    string[] raw = text.Replace("\r", "").Split('\n');
    for (int i = 1; i < raw.Length; i++) {          // line 1 is the title
      string l = raw[i].Trim();
      if (l.Length == 0 || l.StartsWith("*")) continue;
      if (l.StartsWith("+") && lines.Count > 0) lines[lines.Count - 1] += " " + l.Substring(1).Trim();
      else lines.Add(l);
    }
    foreach (string l in lines) {
      var m = Regex.Match(l, @"^\.model\s+(\S+)\s+(.+)$", RegexOptions.IgnoreCase);
      if (m.Success) models[m.Groups[1].Value.ToUpperInvariant()] = Regex.Replace(m.Groups[2].Value.Trim(), @"\s+", " ");
    }
    foreach (string l in lines) {
      char t = char.ToUpperInvariant(l[0]);
      if ("DQMJ".IndexOf(t) < 0) continue;
      string[] tok = Regex.Split(l, @"\s+");
      for (int k = 1; k < tok.Length; k++)
        if (models.ContainsKey(tok[k].ToUpperInvariant())) {
          string name = tok[0].ToUpperInvariant();
          elementModel[name] = tok[k].ToUpperInvariant();
          var nodes = new string[k - 1];
          for (int n = 1; n < k; n++) nodes[n - 1] = tok[n].ToLowerInvariant();
          elementNodes[name] = nodes;
          break;
        }
    }
  }

  static readonly Dictionary<char, string[]> PINS = new Dictionary<char, string[]> {
    { 'D', new[] { "A", "K" } }, { 'Q', new[] { "C", "B", "E", "S" } },
    { 'M', new[] { "D", "G", "S", "B" } }, { 'J', new[] { "D", "G", "S" } } };

  // Netlist device name -> Multisim refdes, matched on the nets each pin connects to.
  public static Dictionary<string, string> MapByConnectivity(string xml, Dictionary<string, string[]> elementNodes, List<string> report) {
    var netName = new Dictionary<string, string>();
    foreach (Match m in Regex.Matches(xml, "<Item CiID=\"(\\d+)\" Class=\"CiNode\">\\s*<CiNode Class=\"CiNode\" LocalName=\"&amp;ASC([^\"]*)\""))
      netName[m.Groups[1].Value] = m.Groups[2].Value.ToLowerInvariant();
    var refOf = new Dictionary<string, string>();
    foreach (Match m in Regex.Matches(xml, "<Item CiID=\"(\\d+)\" Class=\"CiComponent\">\\s*<CiComponent Class=\"CiComponent\" LocalName=\"&amp;ASC([^\"]*)\""))
      refOf[m.Groups[1].Value] = m.Groups[2].Value;
    var pinsOf = new Dictionary<string, Dictionary<string, string>>();   // refdes -> pin -> net
    foreach (Match m in Regex.Matches(xml, "<Item CiID=\"\\d+\" Class=\"CiPort\">\\s*<CiPort Class=\"CiPort\" LocalName=\"&amp;ASC([^\"]*)\"([^>]*)>(.*?)</CiPort>", RegexOptions.Singleline)) {
      var owner = Regex.Match(m.Groups[2].Value, "Component=\"(\\d+)\"");
      string rd;
      if (!owner.Success || !refOf.TryGetValue(owner.Groups[1].Value, out rd)) continue;
      var nodesPart = m.Groups[3].Value; int ni = nodesPart.LastIndexOf("<Nodes>");
      var nm = Regex.Match(ni < 0 ? "" : nodesPart.Substring(ni), "<Item CiID=\"(\\d+)\"/>");
      string net;
      if (!nm.Success || !netName.TryGetValue(nm.Groups[1].Value, out net)) continue;
      if (!pinsOf.ContainsKey(rd)) pinsOf[rd] = new Dictionary<string, string>();
      pinsOf[rd][m.Groups[1].Value.ToUpperInvariant()] = net;
    }
    var map = new Dictionary<string, string>(); var taken = new HashSet<string>();
    foreach (var kv in elementNodes) {
      string[] pinNames; PINS.TryGetValue(kv.Key[0], out pinNames);
      string found = null;
      if (pinNames != null) {
        foreach (var c in pinsOf) {
          if (taken.Contains(c.Key)) continue;
          bool ok = c.Value.Count == kv.Value.Length;
          for (int i = 0; ok && i < kv.Value.Length; i++) { string net; ok = c.Value.TryGetValue(pinNames[i], out net) && net == kv.Value[i]; }
          if (ok) { found = c.Key; break; }
        }
      }
      if (found == null) { report.Add("UNMATCHED " + kv.Key + " (" + string.Join(",", kv.Value) + "): no component with the same pin nets"); continue; }
      taken.Add(found); map[kv.Key] = found;
      report.Add("MAPPED   netlist " + kv.Key + " (" + string.Join(",", kv.Value) + ") -> Multisim " + found);
    }
    return map;
  }

  // Netlist import always places an NPN virtual BJT (the device type lives only in the ignored .model).
  // Turn one into a PNP virtual BJT: family/type strings in the component, and the emitter arrow of its symbol.
  public static string FlipBjtToPnp(string xml, string refdes, List<string> report) {
    var comp = Regex.Match(xml, "<Item CiID=\"\\d+\" Class=\"CiComponent\">\\s*<CiComponent Class=\"CiComponent\" LocalName=\"&amp;ASC" + Regex.Escape(refdes) + "\" Model=\"\\d+\" SymCompID=\"(\\d+)\"(?:(?!</CiComponent>).)*</CiComponent>", RegexOptions.Singleline);
    if (!comp.Success) { report.Add("WARNING  " + refdes + ": component not found, symbol left as NPN"); return xml; }
    string c = comp.Value;
    string[,] swaps = {
      { "<Item Value=\"&amp;ASCBJT_NPN\"/>", "<Item Value=\"&amp;ASCBJT_PNP\"/>" },
      { "<Item Value=\"&amp;ASCNPN\"/>", "<Item Value=\"&amp;ASCPNP\"/>" },
      { "<Item Value=\"&amp;ASC.MODEL NPN NPN\"/>", "<Item Value=\"&amp;ASC.model PNP PNP\"/>" },
      { "<Item Value=\"&amp;ASCFully configurable n-type BJT\"/>", "<Item Value=\"&amp;ASCFully configurable p-type BJT\"/>" } };
    for (int i = 0; i < swaps.GetLength(0); i++) {
      if (c.IndexOf(swaps[i, 0]) < 0) { report.Add("WARNING  " + refdes + ": not a standard virtual NPN, symbol left as NPN"); return xml; }
      c = c.Replace(swaps[i, 0], swaps[i, 1]);
    }
    string sym = comp.Groups[1].Value;
    var symBlk = Regex.Match(xml, "<Item ID=\"" + sym + "\" Class=\"CIITSymbolComp\">(?:(?!</CIITSymbolComp>).)*</CIITSymbolComp>", RegexOptions.Singleline);
    const string npnArrow = "<Item X=\"60\" Y=\"71\"/>(\\r?\\n)<Item X=\"61\" Y=\"75\"/>\\r?\\n<Item X=\"57\" Y=\"76\"/>\\r?\\n<Item X=\"60\" Y=\"71\"/>";
    const string pnpArrow = "<Item X=\"58\" Y=\"77\"/>$1<Item X=\"57\" Y=\"73\"/>$1<Item X=\"61\" Y=\"72\"/>$1<Item X=\"58\" Y=\"77\"/>";
    if (!symBlk.Success || !Regex.IsMatch(symBlk.Value, npnArrow)) { report.Add("WARNING  " + refdes + ": emitter arrow not found, symbol left as NPN"); return xml; }
    // apply the later block first so the earlier index stays valid
    var edits = new List<Tuple<int, int, string>> {
      Tuple.Create(comp.Index, comp.Length, c),
      Tuple.Create(symBlk.Index, symBlk.Length, Regex.Replace(symBlk.Value, npnArrow, pnpArrow)) };
    edits.Sort((p, q) => q.Item1.CompareTo(p.Item1));
    foreach (var e in edits) xml = xml.Substring(0, e.Item1) + e.Item3 + xml.Substring(e.Item1 + e.Item2);
    report.Add("SYMBOL   " + refdes + ": virtual NPN turned into virtual PNP");
    return xml;
  }

  static string Attr(string s) { return s.Replace("&", "&amp;").Replace("<", "&lt;").Replace("\"", "&quot;"); }

  // Read back every patched component's model text; returns refdes -> "TYPE(params)" as stored in the design.
  public static Dictionary<string, string> ReadBack(string xml) {
    var text = new Dictionary<string, string>();
    foreach (Match m in Regex.Matches(xml, "<Item CiID=\"(\\d+)\" Class=\"CiModel\">\\s*<CiModel Class=\"CiModel\" LocalName=\"&amp;ASC[^\"]*\" ChangedByUser=\"[01]\"(?:(?!</CiModel>).)*?<CiaCString Class=\"CiaCString\" String=\"&amp;ASC\\.[Mm][Oo][Dd][Ee][Ll]\\s+\\S+\\s+([^\"]*)\"", RegexOptions.Singleline))
      text[m.Groups[1].Value] = m.Groups[2].Value.Replace("&quot;", "\"").Replace("&lt;", "<").Replace("&amp;", "&").Trim();
    var result = new Dictionary<string, string>();
    foreach (Match c in Regex.Matches(xml, "<CiComponent Class=\"CiComponent\" LocalName=\"&amp;ASC([^\"]*)\" Model=\"(\\d+)\"")) {
      string t; if (text.TryGetValue(c.Groups[2].Value, out t)) result[c.Groups[1].Value.ToUpperInvariant()] = t;
    }
    return result;
  }

  // ---- patch: give every netlist semiconductor its own netlist model text ----
  public static string Patch(string xml, Dictionary<string, string> elementModel, Dictionary<string, string> models, List<string> report) {
    // components: refdes -> CiModel id
    var comp = new Dictionary<string, string>();
    foreach (Match m in Regex.Matches(xml, "<CiComponent Class=\"CiComponent\" LocalName=\"&amp;ASC([^\"]*)\" Model=\"(\\d+)\""))
      comp[m.Groups[1].Value.ToUpperInvariant()] = m.Groups[2].Value;
    // which netlist model each CiModel id should carry; ids shared by devices needing different models get cloned
    var want = new Dictionary<string, string>();            // CiModel id -> netlist model name
    var retarget = new List<string[]>();                    // {refdes, old id, netlist model}
    foreach (var kv in elementModel) {
      string id;
      if (!comp.TryGetValue(kv.Key, out id)) { report.Add("MISSING  " + kv.Key + ": not found in the design"); continue; }
      string cur;
      if (!want.TryGetValue(id, out cur)) want[id] = kv.Value;
      else if (cur != kv.Value) retarget.Add(new[] { kv.Key, id, kv.Value });
    }
    long nextId = 0;
    foreach (Match m in Regex.Matches(xml, "CiID=\"(\\d+)\"")) nextId = Math.Max(nextId, long.Parse(m.Groups[1].Value));
    var cloneOf = new Dictionary<string, string>();          // "oldId|model" -> new id
    foreach (var r in retarget) {
      string key = r[1] + "|" + r[2], nid;
      if (!cloneOf.TryGetValue(key, out nid)) {
        nid = (++nextId).ToString();
        var block = Regex.Match(xml, "<Item CiID=\"" + r[1] + "\" Class=\"CiModel\">.*?</CiModel>\\s*</Item>", RegexOptions.Singleline);
        if (!block.Success) { report.Add("ERROR    " + r[0] + ": model block " + r[1] + " not found"); continue; }
        string copy = block.Value.Replace("<Item CiID=\"" + r[1] + "\"", "<Item CiID=\"" + nid + "\"");
        copy = Regex.Replace(copy, "LocalName=\"&amp;ASC([^\"]*)\"", "LocalName=\"&amp;ASC$1__" + r[2] + "\"");
        xml = xml.Insert(block.Index + block.Length, "\n" + copy);
        xml = xml.Replace("<Item CiID=\"" + r[1] + "\"/>", "<Item CiID=\"" + r[1] + "\"/>\n<Item CiID=\"" + nid + "\"/>");
        cloneOf[key] = nid; want[nid] = r[2];
      }
      xml = Regex.Replace(xml, "(<CiComponent Class=\"CiComponent\" LocalName=\"&amp;ASC)(" + Regex.Escape(r[0]) + ")(\" Model=\")" + r[1] + "\"",
                          "${1}${2}${3}" + nid + "\"", RegexOptions.IgnoreCase);
      report.Add("CLONED   " + r[0] + ": shared model split off for " + r[2]);
    }
    foreach (var kv in want) {
      // stay inside this one CiModel element; Multisim writes ".MODEL" or ".model"
      var mm = Regex.Match(xml, "(<Item CiID=\"" + kv.Key + "\" Class=\"CiModel\">\\s*<CiModel Class=\"CiModel\" LocalName=\"&amp;ASC)([^\"]*)(\" ChangedByUser=\")[01](\"(?:(?!</CiModel>).)*?<CiaCString Class=\"CiaCString\" String=\")&amp;ASC(\\.[Mm][Oo][Dd][Ee][Ll][^\"]*)\"", RegexOptions.Singleline);
      if (!mm.Success) { report.Add("ERROR    model block " + kv.Key + " (" + kv.Value + ") has no .MODEL text"); continue; }
      string localName = mm.Groups[2].Value, body = models[kv.Value];
      string oldType = Regex.Match(mm.Groups[5].Value, "^\\.model\\s+\\S+\\s+([A-Za-z]+)", RegexOptions.IgnoreCase).Groups[1].Value.ToUpperInvariant();
      string newType = Regex.Match(body, "^([A-Za-z]+)").Groups[1].Value.ToUpperInvariant();
      if (oldType != newType) report.Add((oldType == "NPN" && newType == "PNP" ? "NOTE     " : "WARNING  ") + localName + ": imported as " + oldType + ", netlist model " + kv.Value + " is " + newType +
                                         (oldType == "NPN" && newType == "PNP" ? " (BJT symbol is switched to PNP below)" : " (symbol keeps the imported type; replace it in Multisim)"));
      string repl = mm.Groups[1].Value + localName + mm.Groups[3].Value + "1" + mm.Groups[4].Value + "&amp;ASC" + Attr(".MODEL " + localName + " " + body) + "\"";
      xml = xml.Substring(0, mm.Index) + repl + xml.Substring(mm.Index + mm.Length);
      var users = new List<string>();
      foreach (Match c in Regex.Matches(xml, "<CiComponent Class=\"CiComponent\" LocalName=\"&amp;ASC([^\"]*)\" Model=\"" + kv.Key + "\"")) users.Add(c.Groups[1].Value);
      report.Add("PATCHED  " + string.Join(",", users.ToArray()) + " <- " + kv.Value + " " + body);
    }
    return xml;
  }
}
'@

$ErrorActionPreference = "Stop"
$netPath = (Resolve-Path $Netlist).Path
$inPath = (Resolve-Path $Design).Path
if (-not $Out) { $Out = Join-Path (Split-Path $inPath) ([IO.Path]::GetFileNameWithoutExtension($inPath) + "_models.ms14") }

$elementModel = New-Object 'System.Collections.Generic.Dictionary[string,string]'
$models = New-Object 'System.Collections.Generic.Dictionary[string,string]'
$elementNodes = New-Object 'System.Collections.Generic.Dictionary[string,string[]]'
[Ms14]::ParseNetlist([IO.File]::ReadAllText($netPath), $elementModel, $models, $elementNodes)
if ($elementModel.Count -eq 0) { "No D/Q/M/J devices with a .model in the netlist; nothing to patch."; exit 0 }

$xml = [Ms14]::ReadDesign([IO.File]::ReadAllBytes($inPath))
$report = New-Object 'System.Collections.Generic.List[string]'
$map = [Ms14]::MapByConnectivity($xml, $elementNodes, $report)
$byRef = New-Object 'System.Collections.Generic.Dictionary[string,string]'
foreach ($k in $map.Keys) { $byRef[$map[$k].ToUpperInvariant()] = $elementModel[$k] }
$patched = [Ms14]::Patch($xml, $byRef, $models, $report)

# PNP devices were imported as NPN symbols; flip them so the schematic matches the netlist
foreach ($k in $map.Keys) {
  if ($k[0] -eq 'Q' -and $models[$elementModel[$k]] -match '^PNP\b') { $patched = [Ms14]::FlipBjtToPnp($patched, $map[$k], $report) }
}

# verify: every mapped component must now carry exactly its netlist model
$back = [Ms14]::ReadBack($patched)
foreach ($k in $map.Keys) {
  $ref = $map[$k].ToUpperInvariant(); $expect = $models[$elementModel[$k]]
  if (-not $back.ContainsKey($ref) -or $back[$ref] -ne $expect) { $report.Add("ERROR    verify " + $k + " -> " + $ref + ": stored model is [" + $back[$ref] + "]") }
}
$report
if ($report | Where-Object { $_ -match '^(MISSING|ERROR|UNMATCHED)' }) { "PATCH: FAILED, nothing written"; exit 1 }
[IO.File]::WriteAllText($Out, $patched, [Text.Encoding]::ASCII)
"written: $Out"
"PATCH: OK"
exit 0
