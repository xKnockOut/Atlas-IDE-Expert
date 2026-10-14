unit Atlas.Common.Pascal.XmlDoc.Tests;

// Tests für XMLDoc nach Abschnitten (#405, #427), alle Tags und Teilstücke
// samt fehlerhaftem XML (#654) und die Details zu einem Eintrag der
// Vervollständigung (completionItem/resolve, #424).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TXmlDocTests = class
  public
    [Test]
    procedure ReadsAllSections;
    [Test]
    procedure TurnsInnerTagsIntoText;
    [Test]
    procedure PlainCommentIsSummary;
    [Test]
    procedure CollectsCommentAboveSkippingAttributes;
    [Test]
    procedure KeepsCrefNameInSummary;
    [Test]
    procedure NormalizesCrefPrefixesAndGenerics;
    [Test]
    procedure ReadsEverySectionTag;
    [Test]
    procedure ReadsInlineTagsAsRuns;
    [Test]
    procedure CodeBlockKeepsIndentationAndLines;
    [Test]
    procedure ListsAsBulletsNumbersAndTable;
    [Test]
    procedure ResolvesEntities;
    [Test]
    procedure BrokenXmlKeepsAllText;
    [Test]
    procedure InheritDocMergesMissingSections;
    [Test]
    procedure PlainTextAndMarkdownContainNames;
    [Test]
    procedure LongCommentIsNotShortened;
  end;

  [TestFixture]
  TCompletionDetailsTests = class
  public
    [Test]
    procedure DescribesMethodWithXmlDoc;
    [Test]
    procedure ReportsDeprecatedTextAndDirectives;
    [Test]
    procedure LocalVariableWithoutIndexEntry;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Pascal.XmlDoc,
  Atlas.Common.Lsp.Completion;

const
  ListeFile = 'C:\P\Liste.pas';
  UnitListe =
    'unit Liste;'#13#10 +                                                           // 0
    'interface'#13#10 +                                                             // 1
    'type'#13#10 +                                                                  // 2
    '  TListe = class'#13#10 +                                                      // 3
    '  public'#13#10 +                                                              // 4
    '    /// <summary>Hängt <paramref name="S"/> an.</summary>'#13#10 +            // 5
    '    /// <param name="S">Der Text.</param>'#13#10 +                            // 6
    '    /// <returns>Index des neuen Eintrags.</returns>'#13#10 +                   // 7
    '    /// <exception cref="EListError">Liste ist voll.</exception>'#13#10 +      // 8
    '    function Add(const S: string): Integer; virtual;'#13#10 +                  // 9
    '  protected'#13#10 +                                                           // 10
    '    procedure Alt; deprecated ''Stattdessen Neu verwenden'';'#13#10 +          // 11
    '  end;'#13#10 +                                                                // 12
    'implementation'#13#10 +                                                        // 13
    'function TListe.Add(const S: string): Integer;'#13#10 +                        // 14
    'var'#13#10 +                                                                   // 15
    '  Anzahl: Integer;'#13#10 +                                                    // 16
    'begin'#13#10 +                                                                 // 17
    'end;'#13#10 +
    'procedure TListe.Alt;'#13#10 +
    'begin'#13#10 +
    'end;'#13#10 +
    'end.';

function Index: ISymbolIndex;
begin
  Result := TSymbolIndex.Create;
  Result.AddUnit(TIndexExtractor.ExtractText(UnitListe, ListeFile, nil));
end;

function At(ALine, ACharacter: Integer): TTextPosition;
begin
  Result.Line := ALine;
  Result.Character := ACharacter;
end;

{ TXmlDocTests }

procedure TXmlDocTests.ReadsAllSections;
var
  Doc: TXmlDoc;
begin
  Doc := TXmlDoc.Parse(
    ' <summary>Fügt'#10' ein.</summary>'#10 +
    ' <param name="A">Erster.</param>'#10 +
    ' <param name="B">Zweiter.</param>'#10 +
    ' <returns>Summe.</returns>'#10 +
    ' <exception cref="EOverflow">Zu groß.</exception>'#10 +
    ' <remarks>Nur für Ganzzahlen.</remarks>');
  Assert.AreEqual('Fügt ein.', Doc.Summary);
  Assert.AreEqual(2, Integer(Length(Doc.Params)));
  Assert.AreEqual('B', Doc.Params[1].Name);
  Assert.AreEqual('Zweiter.', Doc.Params[1].Text);
  Assert.AreEqual('Summe.', Doc.Returns);
  Assert.AreEqual('EOverflow', Doc.Exceptions[0].Name);
  Assert.AreEqual('Zu groß.', Doc.Exceptions[0].Text);
  Assert.AreEqual('Nur für Ganzzahlen.', Doc.Remarks);
end;

procedure TXmlDocTests.TurnsInnerTagsIntoText;
begin
  Assert.AreEqual('Ruft Foo mit nil auf.', TXmlDoc.CleanText('Ruft <see cref="Foo"/> mit <c>nil</c> auf.'));
  Assert.AreEqual('a < b & c', TXmlDoc.CleanText('a &lt; b &amp; c'));
  Assert.AreEqual('Eins'#10'Zwei', TXmlDoc.CleanText('Eins<para>Zwei</para>'));
end;

procedure TXmlDocTests.PlainCommentIsSummary;
begin
  Assert.AreEqual('Einfacher Kommentar ohne Tags.', TXmlDoc.Parse(' Einfacher Kommentar'#10' ohne Tags.').Summary);
  Assert.IsTrue(TXmlDoc.Parse('').IsEmpty);
end;

procedure TXmlDocTests.CollectsCommentAboveSkippingAttributes;
begin
  Assert.AreEqual(' <summary>X</summary>'#10' <remarks>Y</remarks>', TXmlDoc.CommentAbove(
    ['  /// <summary>X</summary>', '  /// <remarks>Y</remarks>', '  [Weak]', '  FFeld: TObject;'], 3));
  Assert.AreEqual('', TXmlDoc.CommentAbove(['// kein XMLDoc', 'procedure P;'], 1));
end;

function Kinds(const ARuns: TXmlDocRuns): string;
var
  Run: TXmlDocRun;
begin
  Result := '';
  for Run in ARuns do
  begin
    if Result <> '' then
      Result := Result + ',';
    Result := Result + TXmlDoc.RunKindName(Run.Kind);
  end;
end;

procedure TXmlDocTests.KeepsCrefNameInSummary;
var
  Doc: TXmlDoc;
  Section: TXmlDocSection;
begin
  // Beispiel aus #654: Der Name aus <see cref> fehlte im Hover.
  Doc := TXmlDoc.Parse(
    ' <summary>'#10 +
    '   Erstellt die Collection und bindet sie an den besitzenden'#10 +
    '   <see cref="TDBGridFilter"/>.'#10 +
    ' </summary>'#10 +
    ' <param name="AOwner">Der besitzende TDBGridFilter.</param>');
  Assert.AreEqual('Erstellt die Collection und bindet sie an den besitzenden TDBGridFilter.', Doc.Summary);
  Section := Doc.Sections[0];
  Assert.AreEqual('text,ref,text', Kinds(Section.Runs));
  Assert.AreEqual('TDBGridFilter', Section.Runs[1].Text);
  Assert.AreEqual('TDBGridFilter', Section.Runs[1].Target);
  Assert.AreEqual('.', Section.Runs[2].Text);
  Assert.AreEqual('AOwner', Doc.Params[0].Name);
  Assert.AreEqual('Der besitzende TDBGridFilter.', Doc.Params[0].Text);
end;

procedure TXmlDocTests.NormalizesCrefPrefixesAndGenerics;
var
  Doc: TXmlDoc;
begin
  Assert.AreEqual('System.Classes.TList<T>', TXmlDoc.NormalizeCref('T:System.Classes.TList{T}'));
  Assert.AreEqual('TFoo.Bar', TXmlDoc.NormalizeCref(' M:TFoo.Bar '));
  Assert.AreEqual('TDictionary<TKey,TValue>', TXmlDoc.NormalizeCref('TDictionary{TKey,TValue}'));
  Assert.AreEqual('X', TXmlDoc.NormalizeCref('X'));
  Doc := TXmlDoc.Parse('<summary>Siehe <see cref="P:TFoo.Count">Anzahl</see>.</summary>');
  Assert.AreEqual('Anzahl', Doc.Sections[0].Runs[1].Text);
  Assert.AreEqual('TFoo.Count', Doc.Sections[0].Runs[1].Target);
end;

procedure TXmlDocTests.ReadsEverySectionTag;
var
  Doc: TXmlDoc;
  Kind: TXmlDocSectionKind;
  Names: string;
begin
  Doc := TXmlDoc.Parse(
    ' <remarks>Bemerkung.</remarks>'#10 +
    ' <summary>Kurz.</summary>'#10 +
    ' <typeparam name="T">Elementtyp.</typeparam>'#10 +
    ' <param name="A">Erster.</param>'#10 +
    ' <returns>Ergebnis.</returns>'#10 +
    ' <value>Wert der Eigenschaft.</value>'#10 +
    ' <exception cref="T:EFoo">Fehler.</exception>'#10 +
    ' <example>Beispieltext.</example>'#10 +
    ' <seealso cref="TBar"/>'#10 +
    ' <seealso href="https://example.org">Web</seealso>');
  Names := '';
  for Kind := Low(TXmlDocSectionKind) to High(TXmlDocSectionKind) do
    Assert.IsTrue(Doc.IndexOf(Kind) >= 0, 'Abschnitt fehlt: ' + TXmlDoc.SectionName(Kind));
  // Nach Art sortiert, nicht nach Kommentarreihenfolge.
  for Kind := Low(TXmlDocSectionKind) to High(TXmlDocSectionKind) do
    Names := Names + TXmlDoc.SectionName(Doc.Sections[Ord(Kind)].Kind) + ' ';
  Assert.AreEqual('summary param typeparam returns value exception remarks example seealso ', Names);
  Assert.AreEqual('T', Doc.Sections[Doc.IndexOf(TXmlDocSectionKind.TypeParam)].Name);
  Assert.AreEqual('EFoo', Doc.Sections[Doc.IndexOf(TXmlDocSectionKind.Exception)].Name);
  Assert.AreEqual('Wert der Eigenschaft.', Doc.Sections[Doc.IndexOf(TXmlDocSectionKind.Value)].Text);
  Assert.AreEqual('Beispieltext.', Doc.Sections[Doc.IndexOf(TXmlDocSectionKind.Example)].Text);
  Assert.AreEqual('ref,text,link', Kinds(Doc.Sections[Doc.IndexOf(TXmlDocSectionKind.SeeAlso)].Runs));
  Assert.AreEqual('TBar, Web (https://example.org)', Doc.Sections[Doc.IndexOf(TXmlDocSectionKind.SeeAlso)].Text);
  Assert.AreEqual('Bemerkung.', Doc.Remarks);
  Assert.AreEqual('Ergebnis.', Doc.Returns);
  Assert.AreEqual('Fehler.', Doc.Exceptions[0].Text);
end;

procedure TXmlDocTests.ReadsInlineTagsAsRuns;
var
  Runs: TXmlDocRuns;
begin
  Runs := TXmlDoc.Parse('<summary>Gibt <see langword="nil"/> für <paramref name="A"/> und ' +
    '<typeparamref name="T"/> zurück, <b>fett</b> <strong>stark</strong> <i>kursiv</i> <em>betont</em>' +
    '<br/>neue Zeile <see href="https://x.org">Link</see> <c>Code</c>.<para>Absatz</para>Ende</summary>').
    Sections[0].Runs;
  Assert.AreEqual('text,keyword,text,paramref,text,paramref,text,text,text,text,text,text,text,text,br,text,' +
    'link,text,code,text,para,text,para,text', Kinds(Runs));
  Assert.AreEqual('nil', Runs[1].Text);
  Assert.AreEqual('A', Runs[3].Text);
  Assert.AreEqual('T', Runs[5].Text);
  Assert.AreEqual('fett', Runs[7].Text);
  Assert.IsTrue(TXmlDocStyle.Bold in Runs[7].Styles);
  Assert.IsTrue(TXmlDocStyle.Bold in Runs[9].Styles);
  Assert.IsTrue(TXmlDocStyle.Italic in Runs[11].Styles);
  Assert.IsTrue(TXmlDocStyle.Italic in Runs[13].Styles);
  Assert.AreEqual('https://x.org', Runs[16].Target);
  Assert.AreEqual('Code', Runs[18].Text);
  Assert.AreEqual('Gibt nil für A und T zurück, fett stark kursiv betont'#10'neue Zeile Link (https://x.org) ' +
    'Code.'#10'Absatz'#10'Ende', TXmlDoc.RunsText(Runs));
end;

procedure TXmlDocTests.CodeBlockKeepsIndentationAndLines;
var
  Doc: TXmlDoc;
  Runs: TXmlDocRuns;
begin
  Doc := TXmlDoc.Parse(TXmlDoc.CommentAbove([
    '  /// <example>So geht es:',
    '  /// <code>',
    '  ///   if A then',
    '  ///     B;',
    '  ///',
    '  ///   C;',
    '  /// </code>',
    '  /// Danach.</example>',
    '  procedure P;'], 8));
  Runs := Doc.Sections[0].Runs;
  Assert.AreEqual('text,codeblock,text', Kinds(Runs));
  Assert.AreEqual('if A then'#10'  B;'#10#10'C;', Runs[1].Text);
  Assert.AreEqual('So geht es:'#10'if A then'#10'  B;'#10#10'C;'#10'Danach.', Doc.Sections[0].Text);
  // Code direkt hinter <code>: die erste Zeile zählt nicht zur Einrückung.
  Doc := TXmlDoc.Parse('<example><code>X := 1;'#10'   Y := 2;'#10'   Z := 3;</code></example>');
  Assert.AreEqual('X := 1;'#10'Y := 2;'#10'Z := 3;', Doc.Sections[0].Runs[0].Text);
end;

procedure TXmlDocTests.ListsAsBulletsNumbersAndTable;
var
  Doc: TXmlDoc;
begin
  Doc := TXmlDoc.Parse('<summary>Arten:<list type="bullet"><item><term>A</term><description>Erstes</description>' +
    '</item><item><description>Zweites</description></item></list>Danach</summary>');
  Assert.AreEqual('text,bullet,text,text,bullet,text,para,text', Kinds(Doc.Sections[0].Runs));
  Assert.IsTrue(TXmlDocStyle.Bold in Doc.Sections[0].Runs[2].Styles, 'term fett');
  Assert.AreEqual('Arten:'#10'• A – Erstes'#10'• Zweites'#10'Danach', Doc.Summary);
  Doc := TXmlDoc.Parse('<summary><list type="number"><item>Eins</item><item>Zwei<list type="bullet">' +
    '<item>Unter</item></list></item><item>Drei</item></list></summary>');
  Assert.AreEqual('1. Eins'#10'2. Zwei'#10'  • Unter'#10'3. Drei', Doc.Summary);
  Assert.AreEqual(2, Doc.Sections[0].Runs[4].Level);
  Doc := TXmlDoc.Parse('<remarks><list type="table"><listheader><term>Name</term><description>Bedeutung' +
    '</description></listheader><item><term>X</term><description>Breite</description></item></list></remarks>');
  Assert.AreEqual('bullet,text,cell,text,bullet,text,cell,text', Kinds(Doc.Sections[0].Runs));
  Assert.IsTrue(TXmlDocStyle.Bold in Doc.Sections[0].Runs[0].Styles, 'Kopfzeile fett');
  Assert.IsFalse(TXmlDocStyle.Bold in Doc.Sections[0].Runs[5].Styles, 'Tabellenzeile normal');
  Assert.AreEqual('Name – Bedeutung'#10'X – Breite', Doc.Remarks);
end;

procedure TXmlDocTests.ResolvesEntities;
begin
  Assert.AreEqual('<>&"''AB'#$D83D#$DE00' &unbekannt; & x', TXmlDoc.CleanText(
    '&lt;&gt;&amp;&quot;&apos;&#65;&#x42;&#x1F600; &unbekannt; & x'));
  Assert.AreEqual('a < b', TXmlDoc.CleanText('a < b'));
  Assert.AreEqual('Ä Ö ü ß', TXmlDoc.CleanText('Ä Ö ü ß'));
end;

procedure TXmlDocTests.BrokenXmlKeepsAllText;
var
  Doc: TXmlDoc;
begin
  // Nicht geschlossenes <summary>: endet am nächsten Abschnitt.
  Doc := TXmlDoc.Parse(' <summary>Offen <see cref="TFoo"/>'#10' <param name="A">Wert</param>');
  Assert.AreEqual('Offen TFoo', Doc.Summary);
  Assert.AreEqual('Wert', Doc.Params[0].Text);
  // Unbekanntes Tag behält den Text, nicht geschlossenes Inline-Tag auch.
  Doc := TXmlDoc.Parse('<summary>Vor <foo bar="1">innen</foo> <b>fett bis Ende</summary>');
  Assert.AreEqual('Vor innen fett bis Ende', Doc.Summary);
  // Endtag ohne Anfang, kaputtes Attribut, "<" ohne Tag.
  Doc := TXmlDoc.Parse('Text</remarks> mit <see cref="X>Rest und 1 < 2');
  Assert.AreEqual('Text mit <see cref="X>Rest und 1 < 2', Doc.Summary);
  // Text außerhalb von Abschnitten gehört zur Zusammenfassung.
  Doc := TXmlDoc.Parse('<summary>Kurz.</summary> Lose Zeile.');
  Assert.AreEqual('Kurz.'#10'Lose Zeile.', Doc.Summary);
  // Hülle wie <member> um die Abschnitte.
  Doc := TXmlDoc.Parse('<member name="M:X"><summary>In Hülle.</summary><returns>R</returns></member>');
  Assert.AreEqual('In Hülle.', Doc.Summary);
  Assert.AreEqual('R', Doc.Returns);
  // Kommentar und CDATA.
  Assert.AreEqual('a <b> c', TXmlDoc.CleanText('a <!-- weg --><![CDATA[<b>]]> c'));
end;

procedure TXmlDocTests.InheritDocMergesMissingSections;
var
  Doc, Base, Merged: TXmlDoc;
begin
  Doc := TXmlDoc.Parse('<inheritdoc/><param name="B">Eigenes B.</param>');
  Assert.IsTrue(Doc.InheritDoc);
  Assert.AreEqual('', Doc.InheritCref);
  Assert.AreEqual('TBase.Run', TXmlDoc.Parse('<inheritdoc cref="M:TBase.Run"/>').InheritCref);
  Base := TXmlDoc.Parse('<summary>Vom Vorfahr.</summary><param name="A">A.</param><param name="B">B alt.</param>');
  Merged := Doc.Inherit(Base);
  Assert.IsFalse(Merged.InheritDoc);
  Assert.AreEqual('Vom Vorfahr.', Merged.Summary);
  Assert.AreEqual(2, Integer(Length(Merged.Params)));
  Assert.AreEqual('B', Merged.Params[0].Name);
  Assert.AreEqual('Eigenes B.', Merged.Params[0].Text);
  Assert.AreEqual('A', Merged.Params[1].Name);
end;

procedure TXmlDocTests.PlainTextAndMarkdownContainNames;
var
  Doc: TXmlDoc;
begin
  Doc := TXmlDoc.Parse('<summary>Ruft <see cref="TFoo.Run"/> mit <paramref name="A"/>.</summary>' +
    '<param name="A">Wert.</param><typeparam name="T">Typ.</typeparam><returns>Summe.</returns>' +
    '<value>V.</value><exception cref="EFoo">Wenn.</exception><remarks>Mehr.</remarks>' +
    '<example>Bsp.</example><seealso cref="TBar"/>');
  Assert.AreEqual('Ruft TFoo.Run mit A.'#10#10'A: Wert.'#10#10'Typparameter:'#10'T: Typ.'#10#10 +
    '→ Summe.'#10'Wert: V.'#10'! EFoo: Wenn.'#10#10'Mehr.'#10#10'Beispiel:'#10'Bsp.'#10#10'Siehe auch: TBar',
    Doc.ToPlainText);
  Assert.AreEqual('Ruft TFoo.Run mit A.'#10#10'Typparameter:'#10'T: Typ.'#10#10'→ Summe.'#10'Wert: V.'#10 +
    '! EFoo: Wenn.'#10#10'Mehr.'#10#10'Beispiel:'#10'Bsp.'#10#10'Siehe auch: TBar', Doc.ToPlainText(False));
  Assert.AreEqual('Ruft `TFoo.Run` mit *A*.'#10#10'*A*: Wert.'#10#10'**Typparameter**'#10#10'*T*: Typ.'#10#10 +
    '→ Summe.'#10#10'Wert: V.'#10#10'! `EFoo`: Wenn.'#10#10'Mehr.'#10#10'**Beispiel**'#10#10'Bsp.'#10#10 +
    'Siehe auch: `TBar`', Doc.ToMarkdown);
end;

procedure TXmlDocTests.LongCommentIsNotShortened;
var
  Lines: TArray<string>;
  Index: Integer;
  Doc: TXmlDoc;
begin
  Lines := ['/// <summary>'];
  for Index := 1 to 40 do
    Lines := Lines + ['/// Zeile ' + IntToStr(Index) + '<br/>'];
  Lines := Lines + ['/// </summary>', 'procedure P;'];
  Doc := TXmlDoc.Parse(TXmlDoc.CommentAbove(Lines, High(Lines)));
  Assert.AreEqual(40, Integer(Length(Doc.Summary.Split([#10]))));
  Assert.IsTrue(Doc.Summary.EndsWith('Zeile 40'));
end;

{ TCompletionDetailsTests }

procedure TCompletionDetailsTests.DescribesMethodWithXmlDoc;
var
  Details, Section: TJSONObject;
  Runs: TJSONArray;
begin
  // Namensposition von "Add" in Zeile 9.
  Details := TLspCompletion.Details(Index, ListeFile, UnitListe, At(9, 13));
  try
    Assert.AreEqual('function Add(const S: string): Integer; virtual;', Details.GetValue<string>('declaration'));
    Assert.AreEqual('Liste', Details.GetValue<string>('unit'));
    Assert.AreEqual('TListe', Details.GetValue<string>('container'));
    Assert.AreEqual('public', Details.GetValue<string>('visibility'));
    Assert.AreEqual('virtual', (Details.GetValue('directives') as TJSONArray).Items[0].Value);
    Assert.AreEqual('Hängt S an.', Details.GetValue<string>('summary'));
    Assert.AreEqual('Index des neuen Eintrags.', Details.GetValue<string>('returns'));
    Assert.AreEqual('S', (Details.GetValue('params') as TJSONArray).Items[0].GetValue<string>('name'));
    Assert.AreEqual('EListError', (Details.GetValue('exceptions') as TJSONArray).Items[0].GetValue<string>('name'));
    Assert.IsNull(Details.GetValue('deprecated'));
    // Dieselbe Struktur wie im Hover (#654).
    Section := Details.GetValue<TJSONArray>('documentation.sections').Items[0] as TJSONObject;
    Assert.AreEqual('summary', Section.GetValue<string>('kind'));
    Runs := Section.GetValue<TJSONArray>('runs');
    Assert.AreEqual('paramref', Runs.Items[1].GetValue<string>('kind'));
    Assert.AreEqual('Hängt S an.'#10#10'S: Der Text.'#10#10'→ Index des neuen Eintrags.'#10 +
      '! EListError: Liste ist voll.', Details.GetValue<string>('documentationText'));
  finally
    Details.Free;
  end;
end;

procedure TCompletionDetailsTests.ReportsDeprecatedTextAndDirectives;
var
  Details: TJSONObject;
begin
  Details := TLspCompletion.Details(Index, ListeFile, UnitListe, At(11, 14));
  try
    Assert.AreEqual('protected', Details.GetValue<string>('visibility'));
    Assert.AreEqual('Stattdessen Neu verwenden', Details.GetValue<string>('deprecated'));
    Assert.AreEqual('deprecated', (Details.GetValue('directives') as TJSONArray).Items[0].Value);
    Assert.IsNull(Details.GetValue('summary'), 'Ohne XMLDoc keine leeren Abschnitte');
  finally
    Details.Free;
  end;
end;

procedure TCompletionDetailsTests.LocalVariableWithoutIndexEntry;
var
  Details: TJSONObject;
begin
  Details := TLspCompletion.Details(Index, ListeFile, UnitListe, At(16, 2));
  try
    Assert.AreEqual('Anzahl: Integer;', Details.GetValue<string>('declaration'));
    Assert.IsNull(Details.GetValue('container'));
  finally
    Details.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TXmlDocTests);
  TDUnitX.RegisterTestFixture(TCompletionDetailsTests);

end.
