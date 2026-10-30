unit Atlas.Common.Rules.Builtin.XmlDoc.Tests;

// Tests der Regel xmldoc-mismatch (#979): Beispiel aus dem Issue samt
// Korrektur, <returns>, nicht wohlgeformtes XML (W1201 bis W1205) mit
// Korrekturen, cref über den Index (W1206), requirePublic, checkReturns,
// Parserprüfung der Optionen und Abschalten. Codes nur, wo dcc meldet (#1383).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TXmlDocRuleTests = class
  public
    [Test]
    procedure IssueExample;
    [Test]
    procedure MatchingDocIsSilent;
    [Test]
    procedure MissingParamsNeedDescribedParams;
    [Test]
    procedure ReturnsChecks;
    [Test]
    procedure MalformedCharacters;
    [Test]
    procedure MalformedTags;
    [Test]
    procedure CrefFromIndex;
    [Test]
    procedure RequirePublic;
    [Test]
    procedure Options;
    [Test]
    procedure CodesOnlyWhereDccReports;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin.XmlDoc,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Configuration.Parser,
  Atlas.Tests.RuleAssert;

/// <summary>Unit mit einer Klasse TKunde aus AMembers.</summary>
function Kunden(const AMembers: string): string;
begin
  Result := 'unit Kunden;'#10'interface'#10'type'#10'  TKunde = class'#10'  public'#10 + AMembers + '  end;'#10 +
    'implementation'#10'end.';
end;

function Findings(const ASource: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.Findings(TXmlDocMismatchRule.Create, ASource);
end;

function Findings(const ASource, AConfig: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.Findings(TXmlDocMismatchRule.Create, ASource, AConfig);
end;

function OnlyFinding(const ASource: string): TRuleFinding;
var
  Found: TArray<TRuleFinding>;
begin
  Found := Findings(ASource);
  Assert.AreEqual(1, Integer(Length(Found)), ASource);
  Result := Found[0];
end;

/// <summary>Offset von APosition in AText mit Zeilen aus #10.</summary>
function OffsetOf(const AText: string; const APosition: TTextPosition): Integer;
var
  Line, Index: Integer;
begin
  Line := 0;
  Index := 1;
  while (Line < APosition.Line) and (Index <= Length(AText)) do
  begin
    if AText[Index] = #10 then
      Inc(Line);
    Inc(Index);
  end;
  Result := Index + APosition.Character;
end;

/// <summary>Wendet die Edits einer Korrektur von hinten nach vorn an, auch über Zeilen.</summary>
function ApplyFix(const AText: string; const AFix: TRuleFix): string;
var
  Index, Start, Stop: Integer;
begin
  Result := AText;
  for Index := High(AFix.Edits) downto 0 do
  begin
    Start := OffsetOf(Result, AFix.Edits[Index].Range.StartPos);
    Stop := OffsetOf(Result, AFix.Edits[Index].Range.EndPos);
    Result := Copy(Result, 1, Start - 1) + AFix.Edits[Index].NewText + Copy(Result, Stop, MaxInt);
  end;
end;

/// <summary>Einziger Treffer mit Korrektur; liefert den korrigierten Text.</summary>
function Fixed(const ASource, AMessage, ATitle: string): string;
var
  Found: TRuleFinding;
begin
  Found := OnlyFinding(ASource);
  Assert.AreEqual(AMessage, Found.Message);
  Assert.AreEqual(1, Integer(Length(Found.Fixes)), AMessage);
  Assert.AreEqual(ATitle, Found.Fixes[0].Title);
  Result := ApplyFix(ASource, Found.Fixes[0]);
end;

{ TXmlDocRuleTests }

procedure TXmlDocRuleTests.IssueExample;
var
  Source, Expected: string;
  Found: TRuleFinding;
begin
  Assert.IsFalse((TXmlDocMismatchRule.Create as IRule).Descriptor.Experimental, 'Standard an');
  Source := Kunden('    /// <summary>Sucht einen Kunden.</summary>'#10 +
    '    /// <param name="Nummer">Kundennummer</param>'#10 +
    '    function Suchen(const Id: Integer; Aktive: Boolean): TKunde;'#10);
  Found := OnlyFinding(Source);
  Assert.AreEqual('<param name="Nummer"> gibt es nicht (wie W1207); Id und Aktive sind nicht beschrieben ' +
    '(wie W1208).', Found.Message);
  Assert.AreEqual(6, Found.Range.StartPos.Line);
  Assert.AreEqual(8, Found.Range.StartPos.Character);
  Expected := Kunden('    /// <summary>Sucht einen Kunden.</summary>'#10 +
    '    /// <param name="Id">Kundennummer</param>'#10 +
    '    /// <param name="Aktive"></param>'#10 +
    '    function Suchen(const Id: Integer; Aktive: Boolean): TKunde;'#10);
  Assert.AreEqual(Expected, Fixed(Source, Found.Message, 'Doku an die Signatur anpassen'));
  TRuleAssert.Silent(TXmlDocMismatchRule.Create, Expected);
end;

procedure TXmlDocRuleTests.MatchingDocIsSilent;
begin
  // Passende Doku, nur Zusammenfassung, <inheritdoc/>, Typen, Properties, Groß-/Kleinschreibung, Entitäten,
  // CDATA, Kommentare, //// als Trennlinie und /// hinter Code.
  TRuleAssert.Silent(TXmlDocMismatchRule.Create, Kunden(
    '    /// <summary>A &lt; B &amp;&amp; C &gt; D, &#169; &#xA9;</summary>'#10 +
    '    /// <param name="id">Nummer</param>'#10 +
    '    /// <param name="Aktive"><c>True</c>: nur aktive<br/></param>'#10 +
    '    /// <returns>Kunde oder <see langword="nil"/></returns>'#10 +
    '    function Suchen(const Id: Integer; Aktive: Boolean): TKunde;'#10 +
    '    /// <summary>Nur Zusammenfassung.</summary>'#10 +
    '    procedure Speichern(const Pfad: string);'#10 +
    '    /// <inheritdoc/>'#10 +
    '    /// <param name="A">A</param>'#10 +
    '    function Laden(const A, B: string): Boolean;'#10 +
    '    /// <summary><![CDATA[a < b]]><!-- x < y --></summary>'#10 +
    '    [Weak]'#10 +
    '    /// <value>Name</value>'#10 +
    '    property Name: string read FName;'#10 +
    '    //////////////////////////////'#10 +
    '    procedure Leer; /// a < b'#10));
end;

procedure TXmlDocRuleTests.MissingParamsNeedDescribedParams;
var
  Source: string;
begin
  // Ohne <param> im Block fehlt nichts (W1208 meldet erst, wenn andere Parameter beschrieben sind).
  TRuleAssert.Silent(TXmlDocMismatchRule.Create, Kunden('    /// <summary>Speichert.</summary>'#10 +
    '    procedure Speichern(const Pfad: string; Neu: Boolean);'#10));
  // Mittlerer Parameter fehlt: an seiner Stelle ergänzt.
  Source := Kunden('    /// <summary>Kopiert.</summary>'#10 +
    '    /// <param name="Quelle">von</param>'#10 +
    '    /// <param name="Ziel">nach</param>'#10 +
    '    procedure Kopieren(const Quelle: string; Anzahl: Integer; const Ziel: string);'#10);
  Assert.AreEqual(Kunden('    /// <summary>Kopiert.</summary>'#10 +
    '    /// <param name="Quelle">von</param>'#10 +
    '    /// <param name="Anzahl"></param>'#10 +
    '    /// <param name="Ziel">nach</param>'#10 +
    '    procedure Kopieren(const Quelle: string; Anzahl: Integer; const Ziel: string);'#10),
    Fixed(Source, 'Anzahl ist nicht beschrieben (wie W1208).', 'Doku an die Signatur anpassen'));
  // Mehr unbekannte als fehlende: die übrigen entfallen samt Zeile.
  Source := Kunden('    /// <summary>Löscht.</summary>'#10 +
    '    /// <param name="Nummer">Kundennummer</param>'#10 +
    '    /// <param name="Grund">warum</param>'#10 +
    '    procedure Loeschen(const Id: Integer);'#10);
  Assert.AreEqual(Kunden('    /// <summary>Löscht.</summary>'#10 +
    '    /// <param name="Id">Kundennummer</param>'#10 +
    '    procedure Loeschen(const Id: Integer);'#10),
    Fixed(Source, '<param name="Nummer"> und <param name="Grund"> gibt es nicht (wie W1207); Id ist nicht ' +
    'beschrieben (wie W1208).',
    'Doku an die Signatur anpassen'));
end;

procedure TXmlDocRuleTests.ReturnsChecks;
var
  Source, Config: string;
  Found: TArray<TRuleFinding>;
begin
  Source := Kunden('    /// <summary>Speichert.</summary>'#10 +
    '    /// <param name="Pfad">Datei</param>'#10 +
    '    /// <returns>nichts</returns>'#10 +
    '    procedure Speichern(const Pfad: string);'#10);
  Assert.AreEqual(Kunden('    /// <summary>Speichert.</summary>'#10 +
    '    /// <param name="Pfad">Datei</param>'#10 +
    '    procedure Speichern(const Pfad: string);'#10),
    Fixed(Source, '<returns> steht an einer Routine ohne Ergebnis.', 'Doku an die Signatur anpassen'));
  // Auch am Konstruktor und ohne <param>.
  Assert.AreEqual(1, Integer(Length(Findings(Kunden('    /// <returns>Objekt</returns>'#10 +
    '    constructor Create;'#10)))));
  // Fehlendes <returns> nur mit requirePublic; sonst gilt die korrigierte Form aus dem Issue als passend.
  Source := Kunden('    /// <summary>Lädt.</summary>'#10 +
    '    /// <param name="Pfad">Datei</param>'#10 +
    '    function Laden(const Pfad: string): Boolean;'#10);
  TRuleAssert.Silent(TXmlDocMismatchRule.Create, Source);
  Config := '{"rules": {"xmldoc-mismatch": {"requirePublic": true}}}';
  Found := Findings(Source, Config);
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('<returns> fehlt.', Found[0].Message);
  Assert.AreEqual(Kunden('    /// <summary>Lädt.</summary>'#10 +
    '    /// <param name="Pfad">Datei</param>'#10 +
    '    /// <returns></returns>'#10 +
    '    function Laden(const Pfad: string): Boolean;'#10), ApplyFix(Source, Found[0].Fixes[0]));
  Found := Findings(Kunden('    /// <summary>Zählt.</summary>'#10'    function Anzahl: Integer;'#10), Config);
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual(Kunden('    /// <summary>Zählt.</summary>'#10'    /// <returns></returns>'#10 +
    '    function Anzahl: Integer;'#10), ApplyFix(Kunden('    /// <summary>Zählt.</summary>'#10 +
    '    function Anzahl: Integer;'#10), Found[0].Fixes[0]));
  // checkReturns aus: beides still.
  Assert.AreEqual(0, Integer(Length(Findings(Source,
    '{"rules": {"xmldoc-mismatch": {"requirePublic": true, "checkReturns": false}}}'))));
  Assert.AreEqual(0, Integer(Length(Findings(Kunden('    /// <returns>Objekt</returns>'#10 +
    '    constructor Create;'#10), '{"rules": {"xmldoc-mismatch": {"checkReturns": false}}}'))));
end;

procedure TXmlDocRuleTests.MalformedCharacters;
var
  Source: string;
begin
  Source := Kunden('    /// <summary>Liefert True, wenn A < B.</summary>'#10'    function Kleiner: Boolean;'#10);
  Assert.AreEqual(StringReplace(Source, 'A < B', 'A &lt; B', []), Fixed(Source,
    'Doku-Kommentar ist kein wohlgeformtes XML: ''<'' muss &lt; heißen.', '''<'' als &lt; schreiben'));
  Source := Kunden('    /// <summary>Wahr bei 1<2.</summary>'#10'    function Kleiner: Boolean;'#10);
  Assert.AreEqual(StringReplace(Source, '1<2', '1&lt;2', []), Fixed(Source,
    'Doku-Kommentar ist kein wohlgeformtes XML: ''<'' muss &lt; heißen.', '''<'' als &lt; schreiben'));
  Source := Kunden('    /// <summary>Wahr bei a<b).</summary>'#10'    function Kleiner: Boolean;'#10);
  Assert.AreEqual(StringReplace(Source, 'a<b)', 'a&lt;b)', []), Fixed(Source,
    'Doku-Kommentar ist kein wohlgeformtes XML: ''<'' muss &lt; heißen (wie W1205).', '''<'' als &lt; schreiben'));
  Source := Kunden('    /// <summary>Müller & Söhne</summary>'#10'    procedure Firma;'#10);
  Assert.AreEqual(StringReplace(Source, ' & ', ' &amp; ', []), Fixed(Source,
    'Doku-Kommentar ist kein wohlgeformtes XML: ''&'' muss &amp; heißen.', '''&'' als &amp; schreiben'));
  Source := Kunden('    /// <summary>A&B Firma</summary>'#10'    procedure Firma;'#10);
  Assert.AreEqual('Doku-Kommentar ist kein wohlgeformtes XML: ''&'' muss &amp; heißen.',
    OnlyFinding(Source).Message);
  Source := Kunden('    /// <summary>A&nbsp;B</summary>'#10'    procedure Firma;'#10);
  Assert.AreEqual(StringReplace(Source, '&nbsp;', '&amp;nbsp;', []), Fixed(Source,
    'Doku-Kommentar ist kein wohlgeformtes XML: &nbsp; ist in XML nicht definiert.',
    '''&'' als &amp; schreiben'));
  Source := Kunden('    /// <summary>Sucht.</summary>'#10'    /// <param name=Id>Nummer</param>'#10 +
    '    procedure Suchen(Id: Integer);'#10);
  Assert.AreEqual(StringReplace(Source, 'name=Id', 'name="Id"', []), Fixed(Source,
    'Doku-Kommentar ist kein wohlgeformtes XML: Wert von name ohne Anführungszeichen.',
    'Anführungszeichen setzen'));
  // Mehrere Zeichenfehler in einem Block: jeder für sich.
  Assert.AreEqual(2, Integer(Length(Findings(Kunden('    /// <summary>a < b und c < d</summary>'#10 +
    '    procedure Vergleich;'#10)))));
end;

procedure TXmlDocRuleTests.MalformedTags;
var
  Source: string;
begin
  // Generischer Typ im Text.
  Source := Kunden('    /// <summary>Liefert eine TList<T>.</summary>'#10'    function Liste: TObject;'#10);
  Assert.AreEqual(StringReplace(Source, 'TList<T>', 'TList&lt;T&gt;', []), Fixed(Source,
    'Doku-Kommentar ist kein wohlgeformtes XML: <T> wird nicht geschlossen.', '<T> als Text schreiben'));
  // Tag ohne sein Attribut ist Text; '…' beginnt keinen Namen.
  Source := Kunden('    /// <summary>Ohne <param> nicht dokumentiert.</summary>'#10'    procedure Laden;'#10);
  Assert.AreEqual(StringReplace(Source, '<param>', '&lt;param&gt;', []), Fixed(Source,
    'Doku-Kommentar ist kein wohlgeformtes XML: <param> wird nicht geschlossen.', '<param> als Text schreiben'));
  Assert.AreEqual('Doku-Kommentar ist kein wohlgeformtes XML: ''<'' muss &lt; heißen.',
    OnlyFinding(Kunden('    /// <summary>Name<…> =</summary>'#10'    procedure Laden;'#10)).Message);
  // Vergessenes Endtag.
  Source := Kunden('    /// <summary>Lädt'#10'    /// <param name="A">Pfad</param>'#10 +
    '    procedure Laden(A: string);'#10);
  Assert.AreEqual(StringReplace(Source, '/// <summary>Lädt', '/// <summary>Lädt</summary>', []), Fixed(Source,
    'Doku-Kommentar ist kein wohlgeformtes XML: <summary> wird nicht geschlossen.', '</summary> ergänzen'));
  Source := Kunden('    /// <summary>Text<para>mehr</summary>'#10'    procedure Laden;'#10);
  Assert.AreEqual(StringReplace(Source, 'mehr</summary>', 'mehr</para></summary>', []), Fixed(Source,
    'Doku-Kommentar ist kein wohlgeformtes XML: <para> wird nicht geschlossen.', '</para> ergänzen'));
  Source := Kunden('    /// <summary>Zeile<br>Zeile</summary>'#10'    procedure Laden;'#10);
  Assert.AreEqual(StringReplace(Source, '<br>', '<br/>', []), Fixed(Source,
    'Doku-Kommentar ist kein wohlgeformtes XML: <br> wird nicht geschlossen.', '<br/> schreiben'));
  Source := Kunden('    /// <summary>Text</summary></b>'#10'    procedure Laden;'#10);
  Assert.AreEqual(StringReplace(Source, '</b>', '', []), Fixed(Source,
    'Doku-Kommentar ist kein wohlgeformtes XML: </b> hat kein öffnendes Tag.', '</b> entfernen'));
  // Nach einem Fehler im Aufbau keine Signaturprüfung (Folgefehler).
  Assert.AreEqual(1, Integer(Length(Findings(Kunden('    /// <summary>Text<para></summary>'#10 +
    '    /// <param name="X">gibt es nicht</param>'#10'    procedure Laden(A: string);'#10)))));
end;

procedure TXmlDocRuleTests.CrefFromIndex;
var
  Index: ISymbolIndex;
  Found: TArray<TRuleFinding>;
  Source: string;
begin
  Index := TSymbolIndex.Create;
  Index.AddUnit(TIndexExtractor.ExtractText('unit System;'#10'interface'#10'type'#10'  TObject = class'#10 +
    '  end;'#10'implementation'#10'end.', 'C:\BDS\source\System.pas', nil));
  Index.AddUnit(TIndexExtractor.ExtractText('unit Vergleich;'#10'interface'#10'type'#10 +
    '  TVergleicher = class'#10'    function Vergleiche(A, B: Integer): Integer;'#10'  end;'#10 +
    'implementation'#10'end.', 'C:\Projekt\Vergleich.pas', nil));
  Source := 'unit Kunden;'#10'interface'#10'uses'#10'  Vergleich;'#10'type'#10'  TKunde = class'#10 +
    '    /// <summary>Wie <see cref="TVergleicher.Vergleich"/>.</summary>'#10 +
    '    /// <seealso cref="TVergleicher.Vergleiche"/>'#10 +
    '    /// <seealso cref="M:TVergleicher.Vergleiche(System.Int32,System.Int32)"/>'#10 +
    '    /// <seealso cref="T:TVergleicher"/>'#10 +
    '    /// <seealso cref="Speichern"/>'#10 +
    '    /// <seealso cref="Vergleich.TVergleicher"/>'#10 +
    '    /// <seealso cref="TList{T}"/>'#10 +
    '    /// <exception cref="EGibtsNicht">nie</exception>'#10 +
    '    procedure Laden;'#10'    procedure Speichern;'#10'  end;'#10'implementation'#10'end.';
  Found := TRuleAssert.IndexFindings(TXmlDocMismatchRule.Create, Source, Index, '', '');
  Assert.AreEqual(2, Integer(Length(Found)));
  Assert.AreEqual('cref "TVergleicher.Vergleich" zeigt auf kein Symbol (wie W1206). ' +
    'Gemeint ist wohl TVergleicher.Vergleiche.', Found[0].Message);
  Assert.AreEqual(1, Integer(Length(Found[0].Fixes)));
  Assert.AreEqual('cref auf TVergleicher.Vergleiche setzen', Found[0].Fixes[0].Title);
  Assert.AreEqual(StringReplace(Source, '"TVergleicher.Vergleich"', '"TVergleicher.Vergleiche"', []),
    ApplyFix(Source, Found[0].Fixes[0]));
  Assert.AreEqual('cref "EGibtsNicht" zeigt auf kein Symbol (wie W1206).', Found[1].Message);
  Assert.AreEqual(0, Integer(Length(Found[1].Fixes)));
  // Ohne Index und mit unbekannter Unit in uses still.
  Assert.AreEqual(0, Integer(Length(Findings(Source))));
  Found := TRuleAssert.IndexFindings(TXmlDocMismatchRule.Create, StringReplace(Source, '  Vergleich;',
    '  Vergleich, Fremd;', []), Index, '', '');
  Assert.AreEqual(0, Integer(Length(Found)));
end;

procedure TXmlDocRuleTests.RequirePublic;
var
  Source, Config: string;
  Found: TArray<TRuleFinding>;
begin
  Config := '{"rules": {"xmldoc-mismatch": {"requirePublic": true}}}';
  Source := 'unit Kunden;'#10'interface'#10'type'#10'  TKunde = class(TBasis)'#10'  private'#10 +
    '    procedure Intern;'#10'  public'#10'    /// <summary>Lädt.</summary>'#10'    procedure Laden;'#10 +
    '    [Weak]'#10'    function Suchen(const Id: Integer): TKunde;'#10'    procedure Paint; override;'#10 +
    '    property Tag;'#10'  published'#10'    property Name: string read FName;'#10'  end;'#10 +
    'implementation'#10'type'#10'  TIntern = class'#10'  public'#10'    procedure Lokal;'#10'  end;'#10'end.';
  Assert.AreEqual(0, Integer(Length(Findings(Source))), 'Standard aus');
  Found := Findings(Source, Config);
  Assert.AreEqual(2, Integer(Length(Found)));
  Assert.AreEqual('Öffentliches Mitglied Suchen hat keinen Doku-Kommentar.', Found[0].Message);
  Assert.AreEqual(10, Found[0].Range.StartPos.Line);
  Assert.AreEqual('Öffentliches Mitglied Name hat keinen Doku-Kommentar.', Found[1].Message);
  Assert.AreEqual('Doku-Kommentar erzeugen', Found[0].Fixes[0].Title);
  Assert.AreEqual(StringReplace(Source, '    [Weak]'#10, '    /// <summary></summary>'#10 +
    '    /// <param name="Id"></param>'#10'    /// <returns></returns>'#10'    [Weak]'#10, []),
    ApplyFix(Source, Found[0].Fixes[0]));
end;

procedure TXmlDocRuleTests.Options;
var
  Source: string;
  Issues: TArray<TConfigurationIssue>;
begin
  Source := Kunden('    /// <param name="Nummer">Kundennummer</param>'#10'    procedure Suchen(Id: Integer);'#10);
  Assert.AreEqual(1, Integer(Length(Findings(Source))));
  Assert.AreEqual(0, Integer(Length(Findings(Source, '{"rules": {"xmldoc-mismatch": "off"}}'))));
  Assert.AreEqual(0, Integer(Length(Findings(Source, '{"rules": {"group:style": "off"}}'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TXmlDocMismatchRule.Create, Source,
    '{"rules": {"xmldoc-mismatch": {"exclude": ["Alt/**"]}}}', 'Alt/Kunden.pas'))));
  TConfigurationParser.Parse('{"rules": {"xmldoc-mismatch": {"requirePublic": "ja", "checkReturns": 1}}}', Issues);
  Assert.AreEqual(2, Integer(Length(Issues)));
end;

/// <summary>Meldungen aller Befunde, je Zeile eine (für Fehlermeldungen der Tests).</summary>
function Messages(const AFound: TArray<TRuleFinding>): string;
var
  Finding: TRuleFinding;
begin
  Result := '';
  for Finding in AFound do
    Result := Result + Finding.Message + sLineBreak;
end;

procedure TXmlDocRuleTests.CodesOnlyWhereDccReports;
const
  // Formen aus Tests/Compilermeldungen (Cm.W1201 bis Cm.W1205), die Delphi 13 mit --doc still übersetzt.
  Silent: array[0..3] of string = ('<summary>Offenes Element', '<summary>A &unbekannt; B</summary>',
    '<summary>A < B</summary>', '<summary a=>Text</summary>');
var
  Found: TArray<TRuleFinding>;
  Finding: TRuleFinding;
  Text: string;
  Source: string;
begin
  for Text in Silent do
  begin
    Found := Findings('unit U;'#10'interface'#10'/// ' + Text + #10'procedure Machen;'#10'implementation'#10 +
      'procedure Machen;'#10'begin'#10'end;'#10'end.');
    Assert.IsTrue(Length(Found) > 0, Text);
    for Finding in Found do
      Assert.IsFalse(Pos('(wie ', Finding.Message) > 0, Text + ': ' + Finding.Message);
  end;
  // Cm.W1204: dcc meldet W1205 einmal je Kommentar; das Endtag dahinter bleibt ohne Code.
  Found := Findings('unit U;'#10'interface'#10'/// <sum(mary>Text</sum(mary>'#10'procedure Machen;'#10 +
    'implementation'#10'procedure Machen;'#10'begin'#10'end;'#10'end.');
  Assert.AreEqual(2, Integer(Length(Found)), Messages(Found));
  Assert.AreEqual('Doku-Kommentar ist kein wohlgeformtes XML: ''<'' muss &lt; heißen (wie W1205).', Found[0].Message);
  Assert.AreEqual('Doku-Kommentar ist kein wohlgeformtes XML: ''<'' muss &lt; heißen.', Found[1].Message);
  // Nur im implementation-Teil dokumentiert dcc nichts: Befund ohne Code.
  Source := 'unit U;'#10'interface'#10'implementation'#10'/// <summary>Macht.</summary>'#10 +
    '/// <param name="AFalsch">x</param>'#10'procedure Machen(AWert: Integer);'#10'begin'#10'end;'#10 +
    '/// <sum(mary>Text</sum(mary>'#10'procedure Lassen;'#10'begin'#10'end;'#10'end.';
  Found := Findings(Source);
  Assert.AreEqual(3, Integer(Length(Found)), Messages(Found));
  Assert.AreEqual('<param name="AFalsch"> gibt es nicht; AWert ist nicht beschrieben.', Found[0].Message);
  Assert.AreEqual('Doku-Kommentar ist kein wohlgeformtes XML: ''<'' muss &lt; heißen.', Found[1].Message);
end;

initialization
  TDUnitX.RegisterTestFixture(TXmlDocRuleTests);

end.
