# Finish a Multisim 14 design (.ms14) that was created by importing a SPICE netlist:
#  1. Multisim's netlist import replaces every D/Q/M/J device with a virtual part that has default
#     parameters (and turns PNP into NPN); write the netlist's .model text back into each device.
#  2. The import also ignores .op/.ac/.tran; set those analyses up, select output voltages, and make
#     the netlist's analysis the active one, so the design simulates like the netlist right away.
#
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File patch-ms14.ps1 <netlist.cir> <imported.ms14> [<out.ms14>] [-Outputs "out,in"]
#   <out.ms14> defaults to <imported>_models.ms14. The output is written as plain XML, which Multisim 14 opens directly.
#   -Outputs: nets whose voltages are plotted; default is out and in when present, otherwise every net.
# Every patched device is read back and checked. Exit 0 on success; on any mismatch nothing is written and exit is 1.

param(
  [Parameter(Mandatory = $true)][string]$Netlist,
  [Parameter(Mandatory = $true)][string]$Design,
  [string]$Out = "",
  [string]$Outputs = ""
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
                                  Dictionary<string, string[]> elementNodes, Dictionary<string, string> elementInst) {
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
          // instance parameters after the model (W=20u L=2u, AREA, M=2 ...), written the way Multisim stores them
          var inst = new List<string>();
          for (int n = k + 1; n < tok.Length; n++) {
            var kv = Regex.Match(tok[n], @"^(\w+)=(.+)$");
            double v;
            if (kv.Success && TrySpiceNumber(kv.Groups[2].Value, out v)) inst.Add(kv.Groups[1].Value.ToUpperInvariant() + "=" + Num(v).ToLowerInvariant());
            else inst.Add(tok[n]);
          }
          if (inst.Count > 0) elementInst[name] = " " + string.Join("  ", inst.ToArray());
          break;
        }
    }
  }

  static readonly Dictionary<char, string[]> PINS = new Dictionary<char, string[]> {
    { 'D', new[] { "A", "K" } }, { 'Q', new[] { "C", "B", "E", "S" } },
    { 'M', new[] { "D", "G", "S", "SUB" } }, { 'J', new[] { "D", "G", "S" } } };

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
      if (found == null) { report.Add("UNMATCHED " + kv.Key + " (" + string.Join(",", kv.Value) + "): no component with the same pin nets. If Multisim placed an unconnected database part instead, the .model name matched a database model (e.g. MP placed MPS2222): rename the model to something distinctive such as PMOS_LOAD and import again"); continue; }
      taken.Add(found); map[kv.Key] = found;
      report.Add("MAPPED   netlist " + kv.Key + " (" + string.Join(",", kv.Value) + ") -> Multisim " + found);
    }
    return map;
  }

  // Netlist import always places the N-type virtual part (the device type lives only in the ignored .model):
  // NPN for Q, MOS_N_4T for M, JFET_N for J. Turn one into its P-type twin: family/type strings in the
  // component, and the arrow of its symbol (the only geometry difference, taken from Multisim's own P parts).
  class PFlip { public string Name; public string[,] Swaps; public int[] NArrow, PArrow; }
  static readonly Dictionary<char, PFlip> PFLIPS = new Dictionary<char, PFlip> {
    { 'Q', new PFlip { Name = "PNP BJT",
      Swaps = new[,] { { "&amp;ASCBJT_NPN", "&amp;ASCBJT_PNP" }, { "&amp;ASCNPN", "&amp;ASCPNP" }, { "&amp;ASC.MODEL NPN NPN", "&amp;ASC.model PNP PNP" },
                       { "&amp;ASCFully configurable n-type BJT", "&amp;ASCFully configurable p-type BJT" } },
      NArrow = new[] { 60, 71, 61, 75, 57, 76 }, PArrow = new[] { 58, 77, 57, 73, 61, 72 } } },
    { 'M', new PFlip { Name = "PMOS",
      Swaps = new[,] { { "&amp;ASCMOS_N_4T", "&amp;ASCMOS_P_4T" }, { "&amp;ASCNMOS", "&amp;ASCPMOS" }, { "&amp;ASC.model NMOS   nmos", "&amp;ASC.model PMOS pmos" },
                       { "&amp;ASC@", "&amp;ASCB" }, { "&amp;ASCFully configurable n-channel MOSFET with a substrate terminal", "&amp;ASCFully configurable p-channel MOSFET with a substrate terminal" },
                       { "Double=\"366.\"", "Double=\"368.\"" } },
      NArrow = new[] { 58, 61, 55, 63, 58, 65 }, PArrow = new[] { 56, 61, 59, 63, 56, 65 } } },
    { 'J', new PFlip { Name = "P-channel JFET",
      Swaps = new[,] { { "&amp;ASCJFET_N", "&amp;ASCJFET_P" }, { "&amp;ASCNJFET", "&amp;ASCPJFET" }, { "&amp;ASC.model NJFET NJF", "&amp;ASC.model PJFET PJF" },
                       { "&amp;ASC@", "&amp;ASCB" }, { "&amp;ASCFully configurable n-channel JFET", "&amp;ASCFully configurable p-channel JFET" } },
      NArrow = new[] { 48, 70, 51, 72, 48, 74 }, PArrow = new[] { 50, 70, 47, 72, 50, 74 } } } };

  static string ArrowPattern(int[] p) {   // closed triangle: three points, then the first again
    string pt = "<Item X=\"{0}\" Y=\"{1}\"/>";
    return string.Format(pt, p[0], p[1]) + "(\\r?\\n)" + string.Format(pt, p[2], p[3]) + "\\r?\\n" + string.Format(pt, p[4], p[5]) + "\\r?\\n" + string.Format(pt, p[0], p[1]);
  }
  static string ArrowText(int[] p) {
    string pt = "<Item X=\"{0}\" Y=\"{1}\"/>";
    return string.Format(pt, p[0], p[1]) + "$1" + string.Format(pt, p[2], p[3]) + "$1" + string.Format(pt, p[4], p[5]) + "$1" + string.Format(pt, p[0], p[1]);
  }

  public static string FlipToPType(string xml, string refdes, char kind, List<string> report) {
    PFlip f = PFLIPS[kind];
    var comp = Regex.Match(xml, "<Item CiID=\"\\d+\" Class=\"CiComponent\">\\s*<CiComponent Class=\"CiComponent\" LocalName=\"&amp;ASC" + Regex.Escape(refdes) + "\" Model=\"\\d+\" SymCompID=\"(\\d+)\"(?:(?!</CiComponent>).)*</CiComponent>", RegexOptions.Singleline);
    if (!comp.Success) { report.Add("WARNING  " + refdes + ": component not found, symbol left as N-type"); return xml; }
    string c = comp.Value;
    for (int i = 0; i < f.Swaps.GetLength(0); i++) {
      // string items are matched whole (<Item Value="..."/>); the Double swap is an attribute
      string from = f.Swaps[i, 0].StartsWith("Double=") ? f.Swaps[i, 0] : "<Item Value=\"" + f.Swaps[i, 0] + "\"/>";
      string to = f.Swaps[i, 1].StartsWith("Double=") ? f.Swaps[i, 1] : "<Item Value=\"" + f.Swaps[i, 1] + "\"/>";
      int at = c.IndexOf(from);
      if (at < 0) { report.Add("WARNING  " + refdes + ": not a standard N-type virtual part (" + f.Swaps[i, 0] + " missing), symbol left as N-type"); return xml; }
      c = c.Substring(0, at) + to + c.Substring(at + from.Length);   // first occurrence only
    }
    var symBlk = Regex.Match(xml, "<Item ID=\"" + comp.Groups[1].Value + "\" Class=\"CIITSymbolComp\">(?:(?!</CIITSymbolComp>).)*</CIITSymbolComp>", RegexOptions.Singleline);
    string nArrow = ArrowPattern(f.NArrow);
    if (!symBlk.Success || !Regex.IsMatch(symBlk.Value, nArrow)) { report.Add("WARNING  " + refdes + ": symbol arrow not found, symbol left as N-type"); return xml; }
    // apply the later block first so the earlier index stays valid
    var edits = new List<Tuple<int, int, string>> {
      Tuple.Create(comp.Index, comp.Length, c),
      Tuple.Create(symBlk.Index, symBlk.Length, Regex.Replace(symBlk.Value, nArrow, ArrowText(f.PArrow))) };
    edits.Sort((p, q) => q.Item1.CompareTo(p.Item1));
    foreach (var e in edits) xml = xml.Substring(0, e.Item1) + e.Item3 + xml.Substring(e.Item1 + e.Item2);
    report.Add("SYMBOL   " + refdes + ": N-type virtual part turned into virtual " + f.Name);
    return xml;
  }

  // ---- analysis setup: Multisim's import ignores .op/.ac/.tran, so write them into the design's SimState ----
  public static double SpiceNumber(string tok) {
    var m = Regex.Match(tok.Trim(), @"^([-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?)(meg|mil|[tgkmunpf])?", RegexOptions.IgnoreCase);
    if (!m.Success) throw new Exception("not a SPICE number: " + tok);
    double v = double.Parse(m.Groups[1].Value, System.Globalization.CultureInfo.InvariantCulture);
    switch (m.Groups[2].Value.ToLowerInvariant()) {
      case "t": v *= 1e12; break; case "g": v *= 1e9; break; case "meg": v *= 1e6; break; case "k": v *= 1e3; break;
      case "m": v *= 1e-3; break; case "mil": v *= 25.4e-6; break; case "u": v *= 1e-6; break;
      case "n": v *= 1e-9; break; case "p": v *= 1e-12; break; case "f": v *= 1e-15; break;
    }
    return v;
  }
  static string Num(double v) { return v.ToString("G12", System.Globalization.CultureInfo.InvariantCulture); }
  public static bool TrySpiceNumber(string tok, out double v) {
    v = 0;
    if (!Regex.IsMatch(tok, @"^[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?(?:meg|mil|[tgkmunpf])?[a-z]*$", RegexOptions.IgnoreCase)) return false;
    v = SpiceNumber(tok); return true;
  }

  // Instance parameters live in the component's first CiaParamList string, which the SPICE template appends as %S0.
  static readonly string ParamListRx = "(<CiaParamList Class=\"CiaParamList\">\\s*<doubles/>\\s*)<strings(?:/>|>(?:(?!</strings>).)*</strings>)";
  public static string SetInstanceParams(string xml, string refdes, string text, List<string> report) {
    var comp = Regex.Match(xml, "<CiComponent Class=\"CiComponent\" LocalName=\"&amp;ASC" + Regex.Escape(refdes) + "\" Model=\"\\d+\"(?:(?!</CiComponent>).)*</CiComponent>", RegexOptions.Singleline);
    if (!comp.Success) { report.Add("ERROR    " + refdes + ": component not found for instance parameters"); return xml; }
    var pl = new Regex(ParamListRx, RegexOptions.Singleline).Match(comp.Value);
    if (!pl.Success) { report.Add("ERROR    " + refdes + ": no instance parameter list"); return xml; }
    string block = comp.Value.Substring(0, pl.Index) + pl.Groups[1].Value + "<strings>\n<Item Value=\"&amp;ASC" + Attr(text) + "\"/>\n</strings>" + comp.Value.Substring(pl.Index + pl.Length);
    report.Add("INSTANCE " + refdes + ":" + text);
    return xml.Substring(0, comp.Index) + block + xml.Substring(comp.Index + comp.Length);
  }
  public static string ReadInstanceParams(string xml, string refdes) {
    var comp = Regex.Match(xml, "<CiComponent Class=\"CiComponent\" LocalName=\"&amp;ASC" + Regex.Escape(refdes) + "\" Model=\"\\d+\"(?:(?!</CiComponent>).)*</CiComponent>", RegexOptions.Singleline);
    if (!comp.Success) return null;
    var pl = new Regex(ParamListRx, RegexOptions.Singleline).Match(comp.Value);
    if (!pl.Success) return null;
    var item = Regex.Match(pl.Value, "<Item Value=\"&amp;ASC([^\"]*)\"/>");
    return item.Success ? item.Groups[1].Value.Replace("&quot;", "\"").Replace("&lt;", "<").Replace("&amp;", "&") : "";
  }

  // Analysis cards of the netlist: kind ("op", "ac", "tran") -> tokens after the card name.
  public static List<string[]> ParseAnalyses(string text) {
    var list = new List<string[]>();
    foreach (string raw in text.Replace("\r", "").Split('\n')) {
      var m = Regex.Match(raw.Trim(), @"^\.(op|ac|tran|dc)\b\s*(.*)$", RegexOptions.IgnoreCase);
      if (!m.Success) continue;
      var tok = new List<string> { m.Groups[1].Value.ToLowerInvariant() };
      foreach (string t in Regex.Split(m.Groups[2].Value.Trim(), @"\s+")) if (t.Length > 0) tok.Add(t);
      list.Add(tok.ToArray());
    }
    return list;
  }

  public static List<string> NetNames(string xml) {
    var nets = new List<string>();
    foreach (Match m in Regex.Matches(xml, "<CiNode Class=\"CiNode\" LocalName=\"&amp;ASC([^\"]*)\"")) {
      string n = m.Groups[1].Value.ToLowerInvariant();
      if (n != "0" && !nets.Contains(n)) nets.Add(n);
    }
    return nets;
  }

  static int CloseBrace(string s, int open) {         // index of the '}' matching s[open] == '{'
    int depth = 0;
    for (int i = open; i < s.Length; i++) { if (s[i] == '{') depth++; else if (s[i] == '}' && --depth == 0) return i; }
    throw new Exception("unbalanced SimState");
  }
  static string SetValue(string sec, string key, string type, string value, int nth) {
    var ms = Regex.Matches(sec, "([\\n{])" + key + ":\\w+\\{[^{}]*\\}");   // first key of a list follows '{'
    if (ms.Count <= nth) throw new Exception("SimState has no " + key);
    var m = ms[nth];
    return sec.Substring(0, m.Index) + m.Groups[1].Value + key + ":" + type + "{" + value + "}" + sec.Substring(m.Index + m.Length);
  }
  // Replace the selected-output list (the "Nodes" list, not "UserNodes") of one analysis section.
  static string SetOutputs(string sec, IEnumerable<string> nets) {
    var m = Regex.Match(sec, "\\nNodes:list\\{");
    if (!m.Success) throw new Exception("SimState section has no Nodes list");
    int open = m.Index + m.Length - 1, close = CloseBrace(sec, open);
    string body = sec.Substring(open + 1, close - open - 1);
    // keep the list's own flags, drop any previous NODE entries
    var keep = new StringBuilder(); int i = 0;
    while (i < body.Length) {
      int nl = body.IndexOf('\n', i); if (nl < 0) nl = body.Length - 1;
      if (body.Substring(i).StartsWith("NODE:list{")) { int c = CloseBrace(body, i + 9); i = c + 1; if (i < body.Length && body[i] == '\r') i++; if (i < body.Length && body[i] == '\n') i++; continue; }
      keep.Append(body.Substring(i, nl - i + 1)); i = nl + 1;
    }
    var nodes = new StringBuilder();
    foreach (string n in nets)
      nodes.Append("NODE:list{GROUP:long{768}\nPLOTDEVICETYPE:long{0}\nTYPE:long{3}\nNAME:string{$" + n + "}\nDESCRIPTION:string{}\nINI_VALUE:double{0}\n}\n");
    return sec.Substring(0, open + 1) + nodes.ToString() + keep.ToString() + sec.Substring(close);
  }

  public static string ConfigureAnalyses(string xml, List<string[]> cards, List<string> outputs, List<string> report) {
    var ssm = Regex.Match(xml, "SimState=\"([^\"]*)\"");
    if (!ssm.Success) { report.Add("ERROR    design has no SimState"); return xml; }
    string ss = ssm.Groups[1].Value, active = null;
    string[,] bounds = { { "op", "OP", "AC", "dcOpPoint", "DC Operating Point" }, { "ac", "AC", "PHASOR", "ac", "AC Sweep" }, { "tran", "TRAN", "FOUR", "transient", "Transient" },
                         { "dc", "DC_SWEEP", "SENS", "dcSweep", "DC Sweep" } };
    foreach (var card in cards) {
      int b = -1;
      for (int k = 0; k < bounds.GetLength(0); k++) if (bounds[k, 0] == card[0]) b = k;
      if (b < 0) { report.Add("WARNING  ." + card[0] + " is not set up automatically; set it in Simulate > Analyses and simulation"); continue; }
      var st = Regex.Match(ss, "\\n" + bounds[b, 1] + ":list\\{"); var en = Regex.Match(ss, "\\n" + bounds[b, 2] + ":list\\{");
      if (!st.Success || !en.Success || en.Index < st.Index) { report.Add("ERROR    SimState has no " + bounds[b, 1] + " section"); continue; }
      string sec = ss.Substring(st.Index, en.Index - st.Index), desc;
      if (card[0] == "ac") {
        if (card.Length < 5) { report.Add("ERROR    .ac needs: dec|oct|lin <points> <fstart> <fstop>"); continue; }
        string fs = Num(SpiceNumber(card[3])), fe = Num(SpiceNumber(card[4]));
        sec = SetValue(sec, "VARIATION", "string", card[1].ToLowerInvariant(), 0);
        sec = SetValue(sec, "NPOINTS_PER_VARIATION", "double", Num(SpiceNumber(card[2])), 0);
        sec = SetValue(sec, "FSTART", "double", fs, 0); sec = SetValue(sec, "FSTOP", "double", fe, 0);
        sec = SetValue(sec, "hrange", "double", fs, 0); sec = SetValue(sec, "hrange", "double", fe, 1);
        desc = "AC " + card[1] + " " + card[2] + " points, " + fs + " Hz to " + fe + " Hz";
      } else if (card[0] == "tran") {
        var nums = new List<string>(); foreach (string t in card) if (Regex.IsMatch(t, @"^[-+.\d]")) nums.Add(t);
        if (nums.Count < 2) { report.Add("ERROR    .tran needs: <tstep> <tstop> [<tstart> [<tmax>]]"); continue; }
        string tstop = Num(SpiceNumber(nums[1])), tstart = nums.Count > 2 ? Num(SpiceNumber(nums[2])) : "0";
        string tmax = Num(SpiceNumber(nums.Count > 3 ? nums[3] : nums[0]));   // like ngspice, cap the step at tstep
        sec = SetValue(sec, "TSTOP", "double", tstop, 0); sec = SetValue(sec, "TSTART", "double", tstart, 0);
        sec = SetValue(sec, "TMAX", "double", tmax, 0);
        desc = "Transient " + tstart + " s to " + tstop + " s, max step " + tmax + " s";
      } else if (card[0] == "dc") {
        // .dc <src> <start> <stop> <step> [<src2> <start2> <stop2> <step2>]; Multisim names sources "v" + refdes, lower case
        if (card.Length < 5 || "VI".IndexOf(char.ToUpperInvariant(card[1][0])) < 0) { report.Add("ERROR    .dc needs: <V or I source> <start> <stop> <step> [second sweep]"); continue; }
        sec = SetValue(sec, "Source1", "string", card[1].Substring(0, 1).ToLowerInvariant() + card[1].ToLowerInvariant(), 0);
        sec = SetValue(sec, "NodeFilterSource1", "long", "7", 0);
        sec = SetValue(sec, "Start1", "double", Num(SpiceNumber(card[2])), 0);
        sec = SetValue(sec, "Stop1", "double", Num(SpiceNumber(card[3])), 0);
        sec = SetValue(sec, "Increment1", "double", Num(SpiceNumber(card[4])), 0);
        desc = "DC sweep " + card[1] + " " + Num(SpiceNumber(card[2])) + " to " + Num(SpiceNumber(card[3])) + " step " + Num(SpiceNumber(card[4]));
        if (card.Length >= 9) {
          sec = SetValue(sec, "UseSource2", "long", "1", 0);
          sec = SetValue(sec, "Source2", "string", card[5].Substring(0, 1).ToLowerInvariant() + card[5].ToLowerInvariant(), 0);
          sec = SetValue(sec, "NodeFilterSource2", "long", "7", 0);
          sec = SetValue(sec, "Start2", "double", Num(SpiceNumber(card[6])), 0);
          sec = SetValue(sec, "Stop2", "double", Num(SpiceNumber(card[7])), 0);
          sec = SetValue(sec, "Increment2", "double", Num(SpiceNumber(card[8])), 0);
          desc += ", then " + card[5] + " " + Num(SpiceNumber(card[6])) + " to " + Num(SpiceNumber(card[7])) + " step " + Num(SpiceNumber(card[8]));
        }
      } else desc = "DC operating point";
      sec = SetValue(sec, "ANALYSIS_ID", "long", "1", 0); sec = SetValue(sec, "PLOT_TITLE", "string", bounds[b, 4], 0);
      sec = SetOutputs(sec, outputs);
      ss = ss.Substring(0, st.Index) + sec + ss.Substring(en.Index);
      if (active == null || card[0] != "op") active = bounds[b, 3];
      report.Add("ANALYSIS " + desc + "; outputs " + string.Join(", ", outputs.ConvertAll(n => "V(" + n + ")").ToArray()));
    }
    if (active == null) return xml;
    xml = xml.Substring(0, ssm.Groups[1].Index) + ss + xml.Substring(ssm.Groups[1].Index + ssm.Groups[1].Length);
    xml = Regex.Replace(xml, "ActiveAnalysis=\"&amp;ASC[^\"]*\"", "ActiveAnalysis=\"&amp;ASC" + active + "\"");
    xml = xml.Replace("SimStateDataInOldVersion=\"1\"", "SimStateDataInOldVersion=\"0\"");
    report.Add("ACTIVE   " + active);
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
      bool flipped = (oldType == "NPN" && newType == "PNP") || (oldType == "NMOS" && newType == "PMOS") || (oldType == "NJF" && newType == "PJF");
      if (oldType != newType) report.Add((flipped ? "NOTE     " : "WARNING  ") + localName + ": imported as " + oldType + ", netlist model " + kv.Value + " is " + newType +
                                         (flipped ? " (symbol is switched to the P-type part below)" : " (symbol keeps the imported type; replace it in Multisim)"));
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
$netText = [IO.File]::ReadAllText($netPath)
$elementInst = New-Object 'System.Collections.Generic.Dictionary[string,string]'
[Ms14]::ParseNetlist($netText, $elementModel, $models, $elementNodes, $elementInst)

$xml = [Ms14]::ReadDesign([IO.File]::ReadAllBytes($inPath))
$report = New-Object 'System.Collections.Generic.List[string]'
$patched = $xml
$map = New-Object 'System.Collections.Generic.Dictionary[string,string]'
if ($elementModel.Count -gt 0) {
  $map = [Ms14]::MapByConnectivity($xml, $elementNodes, $report)
  $byRef = New-Object 'System.Collections.Generic.Dictionary[string,string]'
  foreach ($k in $map.Keys) { $byRef[$map[$k].ToUpperInvariant()] = $elementModel[$k] }
  $patched = [Ms14]::Patch($xml, $byRef, $models, $report)

  # P-type devices (PNP, PMOS, P-channel JFET) were imported as N-type symbols; flip them so the schematic matches the netlist
  foreach ($k in $map.Keys) {
    $kind = [char]::ToUpperInvariant($k[0]); $mtype = $models[$elementModel[$k]]
    if (($kind -eq 'Q' -and $mtype -match '^PNP\b') -or ($kind -eq 'M' -and $mtype -match '^PMOS\b') -or ($kind -eq 'J' -and $mtype -match '^PJF\b')) {
      $patched = [Ms14]::FlipToPType($patched, $map[$k], $kind, $report)
    }
  }

  # instance parameters (W/L, AREA, ...) are dropped by the import as well
  foreach ($k in $map.Keys) {
    if ($elementInst.ContainsKey($k)) { $patched = [Ms14]::SetInstanceParams($patched, $map[$k], $elementInst[$k], $report) }
  }
} else { $report.Add("MODELS   no D/Q/M/J devices with a .model; nothing to write back") }

# analyses: same settings as the netlist, with output voltages selected
$nets = [Ms14]::NetNames($patched)
$outList = New-Object 'System.Collections.Generic.List[string]'
if ($Outputs) {
  foreach ($n in ($Outputs -split '[,\s]+' | Where-Object { $_ })) {
    if ($nets -contains $n.ToLowerInvariant()) { $outList.Add($n.ToLowerInvariant()) } else { $report.Add("ERROR    -Outputs: no net named " + $n) }
  }
} else {
  foreach ($n in 'out', 'in') { if ($nets -contains $n) { $outList.Add($n) } }
  if ($outList.Count -eq 0) { foreach ($n in $nets) { $outList.Add($n) } }
}
$patched = [Ms14]::ConfigureAnalyses($patched, [Ms14]::ParseAnalyses($netText), $outList, $report)

# verify: every mapped component must now carry exactly its netlist model
$back = [Ms14]::ReadBack($patched)
foreach ($k in $map.Keys) {
  $ref = $map[$k].ToUpperInvariant(); $expect = $models[$elementModel[$k]]
  if (-not $back.ContainsKey($ref) -or $back[$ref] -ne $expect) { $report.Add("ERROR    verify " + $k + " -> " + $ref + ": stored model is [" + $back[$ref] + "]") }
  if ($elementInst.ContainsKey($k)) {
    $inst = [Ms14]::ReadInstanceParams($patched, $map[$k])
    if ($inst -ne $elementInst[$k]) { $report.Add("ERROR    verify " + $k + " -> " + $ref + ": stored instance parameters are [" + $inst + "]") }
  }
}
$report
if ($report | Where-Object { $_ -match '^(MISSING|ERROR|UNMATCHED)' }) { "PATCH: FAILED, nothing written"; exit 1 }
[IO.File]::WriteAllText($Out, $patched, [Text.Encoding]::ASCII)
"written: $Out"
"PATCH: OK"
exit 0
