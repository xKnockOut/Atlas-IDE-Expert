unit Atlas.Common.Editing.SlashMenu.Tests;

// Tests für das Erzeugen-Menü auf Serverseite (#719): Orte an der Cursorstelle,
// Ortsregel und Gruppen des Katalogs, Auswahl möglicher Argumente, Ausführen
// über die gedachte Befehlszeile samt Umrechnen der Änderungen, Umschließen
// nur der Markierung und /ctor mit gewählten Feldern.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TSlashMenuTests = class
  public
    [Test]
    procedure PlacesInClassDeclaration;
    [Test]
    procedure PlacesInMethodAndRoutine;
    [Test]
    procedure PlacesOnUnitLevel;
    [Test]
    procedure PlacesInRecordAndInterface;
    [Test]
    procedure PlacesInProgramAndComment;
    [Test]
    procedure FitsByPlaceAndSelection;
    [Test]
    procedure CatalogCommandsAreRegistered;
    /// <summary>Reihenfolge in der Klasse wie im Entwurf (#719, AC7).</summary>
    [Test]
    procedure CatalogOrderInClass;
    [Test]
    procedure RunCtorWithoutTyping;
    [Test]
    procedure RunCtorWithChosenFields;
    [Test]
    procedure RunStatementAfterCursorLine;
    [Test]
    procedure RunSurroundsOnlySelection;
    [Test]
    procedure RunSelectionBeyondBlockFails;
    [Test]
    procedure RunReportsReason;
    [Test]
    procedure ChoicesForClass;
    [Test]
    procedure ChoicesStatic;
    [Test]
    procedure ArgumentChoicesForSortAndFilter;
    /// <summary>#293: Units, Typen, Interfaces, Ausnahmen, Methoden und Regeln als Argumente.</summary>
    [Test]
    procedure ArgumentChoicesFromIndexAndCatalog;
    [Test]
    procedure MapEditsKeepsIndentAndLineBreak;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Editing.SlashCommands,
  Atlas.Common.Editing.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Editing.SlashMenu;

const
  cClassUnit =
    'unit U;'#10 +                                  // 0
    'interface'#10 +                                // 1
    'type'#10 +                                     // 2
    '  TBasis = class'#10 +                         // 3
    '  protected'#10 +                              // 4
    '    procedure Lauf; virtual;'#10 +             // 5
    '    procedure Malen; virtual;'#10 +            // 6
    '  end;'#10 +                                   // 7
    '  TFoo = class(TBasis)'#10 +                   // 8
    '  private'#10 +                                // 9
    '    FListe: TStringList;'#10 +                 // 10
    '    FName: string;'#10 +                       // 11
    '  protected'#10 +                              // 12
    '    procedure Lauf; override;'#10 +            // 13
    '  public'#10 +                                 // 14
    '    property Name: string read FName;'#10 +    // 15
    '  end;'#10 +                                   // 16
    'implementation'#10 +                           // 17
    #10 +                                           // 18
    'procedure TFoo.Lauf;'#10 +                     // 19
    'begin'#10 +                                    // 20
    '  inherited;'#10 +                             // 21
    'end;'#10 +                                     // 22
    #10 +                                           // 23
    'procedure Frei;'#10 +                          // 24
    'begin'#10 +                                    // 25
    '  Schritt1;'#10 +                              // 26
    '  Schritt2;'#10 +                              // 27
    '  Schritt3;'#10 +                              // 28
    'end;'#10 +                                     // 29
    #10 +                                           // 30
    'end.';

function Spot(ALine: Integer): TSlashSpot; overload;
begin
  Result := TSlashSpot.Create(ALine, 0, -1);
end;

function Spot(ALine, AEndLine: Integer): TSlashSpot; overload;
begin
  Result := TSlashSpot.Create(ALine, 0, AEndLine);
end;

function Key(const AEdit: TRuleEdit): Int64;
begin
  Result := Int64(AEdit.Range.StartPos.Line) * 100000 + AEdit.Range.StartPos.Character;
end;

/// <summary>Wendet AEdits (nicht überlappend) auf AText an.</summary>
function Apply(const AText: string; AEdits: TArray<TRuleEdit>): string;
var
  mLines: TArray<string>;
  mEdit: TRuleEdit;
  mOffsets: TArray<Integer>;
  mIndex, mStart, mStop: Integer;
begin
  mLines := AText.Split([#10]);
  SetLength(mOffsets, Length(mLines) + 1);
  mOffsets[0] := 0;
  for mIndex := 0 to High(mLines) do
  begin
    mOffsets[mIndex + 1] := mOffsets[mIndex] + Length(mLines[mIndex]) + 1;
  end;
  // Von hinten nach vorn anwenden, damit frühere Stellen gültig bleiben.
  for mIndex := 1 to High(AEdits) do
  begin
    mStart := mIndex;
    while (mStart > 0) and (Key(AEdits[mStart - 1]) < Key(AEdits[mStart])) do
    begin
      mEdit := AEdits[mStart - 1];
      AEdits[mStart - 1] := AEdits[mStart];
      AEdits[mStart] := mEdit;
      Dec(mStart);
    end;
  end;
  Result := AText;
  for mEdit in AEdits do
  begin
    mStart := mOffsets[mEdit.Range.StartPos.Line] + mEdit.Range.StartPos.Character;
    mStop := mOffsets[mEdit.Range.EndPos.Line] + mEdit.Range.EndPos.Character;
    Result := Copy(Result, 1, mStart) + mEdit.NewText + Copy(Result, mStop + 1, MaxInt);
  end;
end;

function Parses(const AText: string): Boolean;
var
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(AText);
  try
    Result := Length(mTree.Diagnostics) = 0;
  finally
    mTree.Free;
  end;
end;

function RunAt(const AText: string; const ASpot: TSlashSpot; const AName, AArguments: string;
  out AReason: string): string;
var
  mEdits: TArray<TRuleEdit>;
begin
  Result := '';
  if TSlashMenu.Run(TSlashCommandRegistry.Shared, AText, ASpot, TSlashMenuCall.Create(AName, AArguments,
    TSlashEnvironment.Create(nil, nil)), mEdits, AReason) then
  begin
    Result := Apply(AText, mEdits);
  end;
end;

function HasPlace(APlaces: TSlashPlaces; APlace: TSlashPlace): Boolean;
begin
  Result := APlace in APlaces;
end;

procedure TSlashMenuTests.PlacesInClassDeclaration;
var
  mPlaces: TSlashPlaces;
begin
  // Cursor hinter "TFoo = class(TBasis)": die gedachte Zeile kommt dahinter, also in die Klasse.
  mPlaces := TSlashMenu.PlacesAt(cClassUnit, Spot(8));
  Assert.IsTrue(HasPlace(mPlaces, TSlashPlace.ClassBody), 'Kopf der Klasse');
  Assert.IsFalse(HasPlace(mPlaces, TSlashPlace.Routine));
  Assert.IsTrue(HasPlace(TSlashMenu.PlacesAt(cClassUnit, Spot(11)), TSlashPlace.ClassBody), 'Feld');
  Assert.AreEqual('class', string.Join(',', TSlashMenu.PlaceNames(TSlashMenu.PlacesAt(cClassUnit, Spot(14)))));
end;

procedure TSlashMenuTests.PlacesInMethodAndRoutine;
var
  mPlaces: TSlashPlaces;
begin
  // In einer Methode: Routine und Klasse.
  mPlaces := TSlashMenu.PlacesAt(cClassUnit, Spot(21));
  Assert.IsTrue(HasPlace(mPlaces, TSlashPlace.Routine));
  Assert.IsTrue(HasPlace(mPlaces, TSlashPlace.ClassBody));
  // In einer freien Routine nur die Routine.
  mPlaces := TSlashMenu.PlacesAt(cClassUnit, Spot(26));
  Assert.IsTrue(HasPlace(mPlaces, TSlashPlace.Routine));
  Assert.IsFalse(HasPlace(mPlaces, TSlashPlace.ClassBody));
  Assert.AreEqual('routine', string.Join(',', TSlashMenu.PlaceNames(mPlaces)));
end;

procedure TSlashMenuTests.PlacesOnUnitLevel;
begin
  Assert.AreEqual('interface', string.Join(',', TSlashMenu.PlaceNames(TSlashMenu.PlacesAt(cClassUnit, Spot(2)))),
    'type-Abschnitt im interface');
  Assert.AreEqual('implementation',
    string.Join(',', TSlashMenu.PlaceNames(TSlashMenu.PlacesAt(cClassUnit, Spot(23)))), 'zwischen Routinen');
  // Leere Zeile: die gedachte Zeile steht an ihrer Stelle.
  Assert.AreEqual('implementation',
    string.Join(',', TSlashMenu.PlaceNames(TSlashMenu.PlacesAt(cClassUnit, Spot(18)))));
end;

procedure TSlashMenuTests.PlacesInRecordAndInterface;
const
  cText =
    'unit U;'#10'interface'#10'type'#10 +
    '  TPunkt = record'#10 +        // 3
    '    X, Y: Integer;'#10 +       // 4
    '  end;'#10 +
    '  IFoo = interface'#10 +       // 6
    '    procedure Bar;'#10 +       // 7
    '  end;'#10 +
    'implementation'#10'end.';
begin
  Assert.AreEqual('record', string.Join(',', TSlashMenu.PlaceNames(TSlashMenu.PlacesAt(cText, Spot(4)))));
  Assert.AreEqual('interfaceType', string.Join(',', TSlashMenu.PlaceNames(TSlashMenu.PlacesAt(cText, Spot(6)))));
end;

procedure TSlashMenuTests.PlacesInProgramAndComment;
const
  cProgramText = 'library L;'#10#10'procedure P; stdcall;'#10'begin'#10'end;'#10#10'begin'#10'end.';
  cCommentText = 'unit U;'#10'interface'#10'{ Kommentar'#10#10'  weiter }'#10'implementation'#10'end.';
begin
  Assert.AreEqual('program', string.Join(',', TSlashMenu.PlaceNames(TSlashMenu.PlacesAt(cProgramText, Spot(5)))));
  Assert.AreEqual('routine', string.Join(',', TSlashMenu.PlaceNames(TSlashMenu.PlacesAt(cProgramText, Spot(3)))));
  // Im Kommentar passt kein Befehl.
  Assert.AreEqual('', string.Join(',', TSlashMenu.PlaceNames(TSlashMenu.PlacesAt(cCommentText, Spot(3)))));
end;

procedure TSlashMenuTests.FitsByPlaceAndSelection;
var
  mCtor, mTry_, mTodo: TSlashMenuEntry;
begin
  Assert.IsTrue(TSlashMenu.Find('ctor', mCtor));
  Assert.IsTrue(TSlashMenu.Find('try', mTry_));
  Assert.IsTrue(TSlashMenu.Find('TODO', mTodo), 'ohne Groß/Klein');
  Assert.IsTrue(TSlashMenu.Fits(mCtor, [TSlashPlace.ClassBody], False));
  Assert.IsTrue(TSlashMenu.Fits(mCtor, [TSlashPlace.Routine, TSlashPlace.ClassBody], True));
  Assert.IsFalse(TSlashMenu.Fits(mCtor, [TSlashPlace.Routine], False));
  // Umschließen nur mit Markierung in einer Routine.
  Assert.IsFalse(TSlashMenu.Fits(mTry_, [TSlashPlace.Routine], False));
  Assert.IsTrue(TSlashMenu.Fits(mTry_, [TSlashPlace.Routine], True));
  Assert.IsFalse(TSlashMenu.Fits(mTry_, [TSlashPlace.ClassBody], True));
  Assert.IsTrue(TSlashMenu.Fits(mTodo, [TSlashPlace.UnitInterface], False));
  Assert.AreEqual('surround', TSlashMenu.GroupName(mTry_.Group));
  Assert.AreEqual('optional', TSlashMenu.ArgumentName(mCtor.Argument));
  Assert.IsTrue(mCtor.Multi and mCtor.HasChoices);
  Assert.AreEqual(', ', mCtor.Separator);
  Assert.IsFalse(TSlashMenu.Find('format', mCtor), 'Umbauten stehen nicht im Menü');
end;

procedure TSlashMenuTests.CatalogCommandsAreRegistered;
var
  mItem: TSlashMenuEntry;
  mCommand: TSlashCommand;
  mNames: string;
begin
  mNames := '';
  for mItem in TSlashMenu.Catalog do
  begin
    Assert.IsTrue(TSlashCommandRegistry.Shared.Find(mItem.Name, mCommand), mItem.Name);
    Assert.AreNotEqual<TSlashPlaces>([], mItem.Places, 'Ortsregel: ' + mItem.Name);
    Assert.AreEqual(0, Pos(',' + mItem.Name + ',', mNames), 'doppelt: ' + mItem.Name);
    mNames := mNames + ',' + mItem.Name + ',';
  end;
  Assert.AreEqual('ctor', TSlashMenu.Catalog[0].Name, 'Konstruktor zuerst wie im Mockup');
end;

procedure TSlashMenuTests.CatalogOrderInClass;
var
  mEntry: TSlashMenuEntry;
  mNames: TArray<string>;
begin
  mNames := nil;
  for mEntry in TSlashMenu.Catalog do
  begin
    if TSlashMenu.Fits(mEntry, [TSlashPlace.ClassBody], False) and (Length(mNames) < 6) then
    begin
      mNames := mNames + [mEntry.Name];
    end;
  end;
  Assert.AreEqual('ctor,dtor,prop,override,equals,impl', string.Join(',', mNames));
end;

procedure TSlashMenuTests.RunCtorWithoutTyping;
var
  mText, mReason: string;
begin
  mText := RunAt(cClassUnit, Spot(8), 'ctor', '', mReason);
  Assert.AreEqual('', mReason);
  Assert.IsTrue(Pos('constructor Create(const AListe: TStringList; const AName: string);', mText) > 0, mText);
  Assert.IsTrue(Pos('constructor TFoo.Create(const AListe: TStringList; const AName: string);', mText) > 0, mText);
  Assert.AreEqual(0, Pos('/ctor', mText), 'keine Befehlszeile');
  // Die Zeilen der Klasse bleiben unverändert und in der Reihenfolge.
  Assert.IsTrue(Pos('  TFoo = class(TBasis)'#10'  private'#10'    FListe: TStringList;', mText) > 0, mText);
  Assert.IsTrue(Parses(mText), mText);
end;

procedure TSlashMenuTests.RunCtorWithChosenFields;
var
  mText, mReason: string;
begin
  mText := RunAt(cClassUnit, Spot(11), 'ctor', 'FName', mReason);
  Assert.IsTrue(Pos('constructor Create(const AName: string);', mText) > 0, mText);
  Assert.AreEqual(0, Pos('AListe', mText), mText);
  // Ohne F geht auch, mehrere mit Komma.
  mText := RunAt(cClassUnit, Spot(11), 'ctor', 'Name, Liste', mReason);
  Assert.IsTrue(Pos('constructor Create(const AListe: TStringList; const AName: string);', mText) > 0, mText);
  Assert.AreEqual('', RunAt(cClassUnit, Spot(11), 'ctor', 'FGibts', mReason));
  Assert.IsTrue(Pos('kein Feld FGibts in TFoo', mReason) > 0, mReason);
end;

procedure TSlashMenuTests.RunStatementAfterCursorLine;
var
  mText, mReason: string;
begin
  // Cursor in "Schritt1;": /raise kommt dahinter, eingerückt wie die Anweisungen.
  mText := RunAt(cClassUnit, Spot(26), 'raise', 'EFehler Kaputt', mReason);
  Assert.AreEqual('', mReason);
  Assert.IsTrue(Pos('  Schritt1;'#10'  raise EFehler.Create(', mText) > 0, mText);
  Assert.IsTrue(Pos('Kaputt', mText) > 0, mText);
  Assert.IsTrue(Pos(#10'  Schritt2;', mText) > 0, mText);
  Assert.IsTrue(Parses(mText), mText);
end;

procedure TSlashMenuTests.RunSurroundsOnlySelection;
var
  mText, mReason: string;
begin
  // Markierung über Schritt1 und Schritt2: Schritt3 bleibt außerhalb.
  mText := RunAt(cClassUnit, Spot(26, 27), 'ifdef', 'DEBUG', mReason);
  Assert.AreEqual('', mReason);
  Assert.IsTrue(Pos('begin'#10'  {$IFDEF DEBUG}'#10'  Schritt1;'#10'  Schritt2;'#10'  {$ENDIF}'#10'  Schritt3;'#10'end;',
    mText) > 0, mText);
  mText := RunAt(cClassUnit, Spot(27, 27), 'except', '', mReason);
  Assert.IsTrue(Pos('  Schritt1;'#10'  try'#10'    Schritt2;'#10'  except', mText) > 0, mText);
  Assert.IsTrue(Pos('  end;'#10'  Schritt3;'#10'end;', mText) > 0, mText);
  Assert.IsTrue(Parses(mText), mText);
end;

procedure TSlashMenuTests.RunSelectionBeyondBlockFails;
var
  mReason: string;
begin
  // Von Schritt3 bis in die nächste Zeile nach "end;": nicht im selben Block.
  Assert.AreEqual('', RunAt(cClassUnit, Spot(28, 30), 'ifdef', 'DEBUG', mReason));
  Assert.IsTrue(Pos('Markierung', mReason) > 0, mReason);
end;

procedure TSlashMenuTests.RunReportsReason;
var
  mReason: string;
  mEdits: TArray<TRuleEdit>;
begin
  Assert.AreEqual('', RunAt(cClassUnit, Spot(26), 'ctor', '', mReason));
  Assert.AreEqual('/ctor gilt nur in einer Klasse oder einer ihrer Methoden', mReason);
  Assert.IsFalse(TSlashMenu.Run(TSlashCommandRegistry.Shared, cClassUnit, Spot(8), TSlashMenuCall.Create('ctor', '',
    TSlashEnvironment.Create(nil, ['ctor'], nil, '', '', nil)), mEdits, mReason));
  Assert.IsTrue(Pos('abgeschaltet', mReason) > 0, mReason);
  Assert.IsFalse(TSlashMenu.Run(TSlashCommandRegistry.Shared, cClassUnit, Spot(8), TSlashMenuCall.Create('gibtsnicht',
    '', TSlashEnvironment.Create(nil, nil)), mEdits, mReason));
  Assert.AreEqual('Unbekannter Schnellbefehl /gibtsnicht', mReason);
end;

procedure TSlashMenuTests.ChoicesForClass;
begin
  Assert.AreEqual('FListe,FName', string.Join(',', TSlashMenu.Choices(cClassUnit, Spot(11), 'ctor', nil)));
  // Lauf überschreibt TFoo schon; Malen bleibt.
  Assert.AreEqual('Malen', string.Join(',', TSlashMenu.Choices(cClassUnit, Spot(11), 'override', nil)));
  // FName hat schon die Property Name.
  Assert.AreEqual('FListe', string.Join(',', TSlashMenu.Choices(cClassUnit, Spot(11), 'encapsulate', nil)));
  Assert.AreEqual('FListe,FName', string.Join(',', TSlashMenu.Choices(cClassUnit, Spot(11), 'equals', nil)));
  // Außerhalb der Klasse keine Felder.
  Assert.AreEqual(0, Integer(Length(TSlashMenu.Choices(cClassUnit, Spot(26), 'ctor', nil))));
end;

procedure TSlashMenuTests.ChoicesStatic;
begin
  Assert.IsTrue(MatchText('WM_SIZE', TSlashMenu.Choices(cClassUnit, Spot(11), 'msg', nil)));
  Assert.IsTrue(MatchText('Implicit', TSlashMenu.Choices(cClassUnit, Spot(11), 'operator', nil)));
  Assert.IsTrue(MatchText('<>', TSlashMenu.Choices(cClassUnit, Spot(11), 'operator', nil)));
  Assert.AreEqual('DEBUG', TSlashMenu.Choices(cClassUnit, Spot(26), 'ifdef', nil)[0]);
  Assert.AreEqual(0, Integer(Length(TSlashMenu.Choices(cClassUnit, Spot(11), 'prop', nil))), 'freie Eingabe');
end;

procedure TSlashMenuTests.ArgumentChoicesForSortAndFilter;
const
  cText =
    'unit U;'#10'interface'#10'type'#10'  TKunde = class'#10'  public'#10'    Name: string;'#10 +
    '    property Umsatz: Double read FUmsatz;'#10'  end;'#10'implementation'#10 +
    'procedure P;'#10'var'#10'  Kunden: TObjectList<TKunde>;'#10'begin'#10'  %s'#10'end;'#10'end.';
begin
  // Menü: ohne Argument die Sammlungen; beim Tippen nach dem Leerzeichen die Mitglieder des Elementtyps.
  Assert.AreEqual('Kunden', string.Join(',', TSlashMenu.Choices(Format(cText, ['']), Spot(13), 'sort', nil)));
  Assert.AreEqual('Kunden', string.Join(',', TSlashMenu.ArgumentChoices(Format(cText, ['/filter Ku']), 13, 'filter',
    'Ku', nil)));
  Assert.AreEqual('Name,Umsatz', string.Join(',', TSlashMenu.ArgumentChoices(Format(cText, ['/sort Kunden -']), 13,
    'sort', 'Kunden -', nil)));
  Assert.AreEqual(0, Integer(Length(TSlashMenu.ArgumentChoices(Format(cText, ['/list ']), 13, 'list', '', nil))));
end;

procedure TSlashMenuTests.ArgumentChoicesFromIndexAndCatalog;
const
  cLibrary_ =
    'unit Kunden.Daten;'#10'interface'#10'type'#10 +
    '  TKunde = class'#10'    procedure Laden;'#10'  end;'#10 +
    '  TKundenArt = (kaNeu, kaAlt);'#10 +
    '  IExporter = interface'#10'  end;'#10 +
    '  EImportFehler = class(Exception)'#10'  end;'#10 +
    'implementation'#10'end.';
var
  mIndex: ISymbolIndex;
  mTree: TSyntaxTree;

  function Choices(const AName, AArguments: string): string;
  begin
    Result := string.Join(',', TSlashMenu.ArgumentChoices(cClassUnit, 11, AName, AArguments, mIndex));
  end;

begin
  mIndex := TSymbolIndex.Create;
  mTree := TPascalParser.Parse(cLibrary_);
  try
    mIndex.AddUnit(TIndexExtractor.Extract(mTree, 'C:\P\Kunden.Daten.pas'));
  finally
    mTree.Free;
  end;
  Assert.AreEqual('Kunden.Daten', Choices('uses', 'Ku'));
  Assert.AreEqual('Kunden.Daten', Choices('open', ''));
  Assert.AreEqual('', Choices('uses', 'Vcl'));
  // Typen erst hinter dem Doppelpunkt; nur Typen auf Unit-Ebene.
  Assert.AreEqual('', Choices('var', 'Liste'));
  Assert.AreEqual('TKunde,TKundenArt', Choices('var', 'Liste: TKu'));
  Assert.AreEqual('TKunde,TKundenArt', Choices('field', 'FKunde:TK'));
  Assert.AreEqual('TKunde,TKundenArt', Choices('helper', 'TK'));
  Assert.AreEqual('', Choices('helper', 'TKunde Na'));
  Assert.AreEqual('IExporter', Choices('intf', ''));
  Assert.AreEqual('EImportFehler', Choices('raise', ''));
  Assert.AreEqual('', Choices('raise', 'EImportFehler Dat'), 'die Meldung ist frei');
  // Methoden zum Überschreiben (ohne Index aus der Datei) und Regeln aus dem Katalog.
  Assert.AreEqual('Malen', string.Join(',', TSlashMenu.ArgumentChoices(cClassUnit, 11, 'override', 'Ma', nil)));
  Assert.AreEqual('unused-local,unused-parameter', string.Join(',', TSlashMenu.ArgumentChoices(cClassUnit, 11,
    'ignore', 'unused-', nil, ['with-statement', 'unused-parameter', 'unused-local'])));
  Assert.AreEqual(0, Integer(Length(TSlashMenu.ArgumentChoices(cClassUnit, 11, 'ignore', 'unused-local Gr', nil,
    ['unused-local']))));
  Assert.AreEqual<TSlashArgumentKind>(TSlashArgumentKind.Types, TSlashMenu.ArgumentKind('var', 'X: T'));
  Assert.AreEqual('TK', TSlashMenu.CurrentWord('FKunde:TK'));
end;

procedure TSlashMenuTests.MapEditsKeepsIndentAndLineBreak;
var
  mEdits: TArray<TRuleEdit>;
begin
  // Gedachter Text: Zeile 1 = "  /x". Ersetzt wird nur "/x": Einrückung und Zeilenende bleiben stehen.
  mEdits := TSlashMenu.MapEdits([TRuleEdit.Create(TTextRange.Create(1, 2, 1, 4), 'Neu;')], 1, '  /x', #10);
  Assert.AreEqual(1, Integer(Length(mEdits)));
  Assert.AreEqual(1, mEdits[0].Range.StartPos.Line);
  Assert.AreEqual(0, mEdits[0].Range.StartPos.Character);
  Assert.AreEqual(1, mEdits[0].Range.EndPos.Line);
  Assert.AreEqual(0, mEdits[0].Range.EndPos.Character);
  Assert.AreEqual('  Neu;'#10, mEdits[0].NewText);
  // Zeile samt Zeilenende entfernt: entfällt; spätere Zeilen rücken eine Zeile nach oben.
  mEdits := TSlashMenu.MapEdits([TRuleEdit.Create(TTextRange.Create(1, 0, 2, 0), ''),
    TRuleEdit.Create(TTextRange.Create(5, 3, 5, 3), 'X')], 1, '  /x', #10);
  Assert.AreEqual(1, Integer(Length(mEdits)));
  Assert.AreEqual(4, mEdits[0].Range.StartPos.Line);
  Assert.AreEqual(3, mEdits[0].Range.StartPos.Character);
  // Davor bleibt alles, wie es ist.
  mEdits := TSlashMenu.MapEdits([TRuleEdit.Create(TTextRange.Create(0, 1, 0, 2), 'Y')], 1, '  /x', #10);
  Assert.AreEqual(0, mEdits[0].Range.StartPos.Line);
  Assert.AreEqual(1, mEdits[0].Range.StartPos.Character);
  Assert.AreEqual('Y', mEdits[0].NewText);
end;

initialization
  TDUnitX.RegisterTestFixture(TSlashMenuTests);

end.
