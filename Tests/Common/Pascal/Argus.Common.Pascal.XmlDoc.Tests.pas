unit Argus.Common.Pascal.XmlDoc.Tests;

// Tests für XMLDoc nach Abschnitten (#405, #427) und die Details zu einem
// Eintrag der Vervollständigung (completionItem/resolve, #424).

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
  Argus.Common.Documents.Contract,
  Argus.Common.Index.Contract,
  Argus.Common.Index.SymbolIndex,
  Argus.Common.Index.Extractor,
  Argus.Common.Pascal.XmlDoc,
  Argus.Common.Lsp.Completion;

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

{ TCompletionDetailsTests }

procedure TCompletionDetailsTests.DescribesMethodWithXmlDoc;
var
  Details: TJSONObject;
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
