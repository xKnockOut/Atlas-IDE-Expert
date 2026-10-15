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
  Atlas.Common.Editing.SlashMenu;

const
  ClassUnit =
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
  Lines: TArray<string>;
  Edit: TRuleEdit;
  Offsets: TArray<Integer>;
  Index, Start, Stop: Integer;
begin
  Lines := AText.Split([#10]);
  SetLength(Offsets, Length(Lines) + 1);
  Offsets[0] := 0;
  for Index := 0 to High(Lines) do
    Offsets[Index + 1] := Offsets[Index] + Length(Lines[Index]) + 1;
  // Von hinten nach vorn anwenden, damit frühere Stellen gültig bleiben.
  for Index := 1 to High(AEdits) do
  begin
    Start := Index;
    while (Start > 0) and (Key(AEdits[Start - 1]) < Key(AEdits[Start])) do
    begin
      Edit := AEdits[Start - 1];
      AEdits[Start - 1] := AEdits[Start];
      AEdits[Start] := Edit;
      Dec(Start);
    end;
  end;
  Result := AText;
  for Edit in AEdits do
  begin
    Start := Offsets[Edit.Range.StartPos.Line] + Edit.Range.StartPos.Character;
    Stop := Offsets[Edit.Range.EndPos.Line] + Edit.Range.EndPos.Character;
    Result := Copy(Result, 1, Start) + Edit.NewText + Copy(Result, Stop + 1, MaxInt);
  end;
end;

function Parses(const AText: string): Boolean;
var
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(AText);
  try
    Result := Length(Tree.Diagnostics) = 0;
  finally
    Tree.Free;
  end;
end;

function RunAt(const AText: string; const ASpot: TSlashSpot; const AName, AArguments: string;
  out AReason: string): string;
var
  Edits: TArray<TRuleEdit>;
begin
  Result := '';
  if TSlashMenu.Run(TSlashCommandRegistry.Shared, AText, ASpot, AName, AArguments, nil, nil, '', '', nil, Edits,
    AReason) then
    Result := Apply(AText, Edits);
end;

function HasPlace(APlaces: TSlashPlaces; APlace: TSlashPlace): Boolean;
begin
  Result := APlace in APlaces;
end;

procedure TSlashMenuTests.PlacesInClassDeclaration;
var
  Places: TSlashPlaces;
begin
  // Cursor hinter "TFoo = class(TBasis)": die gedachte Zeile kommt dahinter, also in die Klasse.
  Places := TSlashMenu.PlacesAt(ClassUnit, Spot(8));
  Assert.IsTrue(HasPlace(Places, TSlashPlace.ClassBody), 'Kopf der Klasse');
  Assert.IsFalse(HasPlace(Places, TSlashPlace.Routine));
  Assert.IsTrue(HasPlace(TSlashMenu.PlacesAt(ClassUnit, Spot(11)), TSlashPlace.ClassBody), 'Feld');
  Assert.AreEqual('class', string.Join(',', TSlashMenu.PlaceNames(TSlashMenu.PlacesAt(ClassUnit, Spot(14)))));
end;

procedure TSlashMenuTests.PlacesInMethodAndRoutine;
var
  Places: TSlashPlaces;
begin
  // In einer Methode: Routine und Klasse.
  Places := TSlashMenu.PlacesAt(ClassUnit, Spot(21));
  Assert.IsTrue(HasPlace(Places, TSlashPlace.Routine));
  Assert.IsTrue(HasPlace(Places, TSlashPlace.ClassBody));
  // In einer freien Routine nur die Routine.
  Places := TSlashMenu.PlacesAt(ClassUnit, Spot(26));
  Assert.IsTrue(HasPlace(Places, TSlashPlace.Routine));
  Assert.IsFalse(HasPlace(Places, TSlashPlace.ClassBody));
  Assert.AreEqual('routine', string.Join(',', TSlashMenu.PlaceNames(Places)));
end;

procedure TSlashMenuTests.PlacesOnUnitLevel;
begin
  Assert.AreEqual('interface', string.Join(',', TSlashMenu.PlaceNames(TSlashMenu.PlacesAt(ClassUnit, Spot(2)))),
    'type-Abschnitt im interface');
  Assert.AreEqual('implementation',
    string.Join(',', TSlashMenu.PlaceNames(TSlashMenu.PlacesAt(ClassUnit, Spot(23)))), 'zwischen Routinen');
  // Leere Zeile: die gedachte Zeile steht an ihrer Stelle.
  Assert.AreEqual('implementation',
    string.Join(',', TSlashMenu.PlaceNames(TSlashMenu.PlacesAt(ClassUnit, Spot(18)))));
end;

procedure TSlashMenuTests.PlacesInRecordAndInterface;
const
  Text =
    'unit U;'#10'interface'#10'type'#10 +
    '  TPunkt = record'#10 +        // 3
    '    X, Y: Integer;'#10 +       // 4
    '  end;'#10 +
    '  IFoo = interface'#10 +       // 6
    '    procedure Bar;'#10 +       // 7
    '  end;'#10 +
    'implementation'#10'end.';
begin
  Assert.AreEqual('record', string.Join(',', TSlashMenu.PlaceNames(TSlashMenu.PlacesAt(Text, Spot(4)))));
  Assert.AreEqual('interfaceType', string.Join(',', TSlashMenu.PlaceNames(TSlashMenu.PlacesAt(Text, Spot(6)))));
end;

procedure TSlashMenuTests.PlacesInProgramAndComment;
const
  ProgramText = 'library L;'#10#10'procedure P; stdcall;'#10'begin'#10'end;'#10#10'begin'#10'end.';
  CommentText = 'unit U;'#10'interface'#10'{ Kommentar'#10#10'  weiter }'#10'implementation'#10'end.';
begin
  Assert.AreEqual('program', string.Join(',', TSlashMenu.PlaceNames(TSlashMenu.PlacesAt(ProgramText, Spot(5)))));
  Assert.AreEqual('routine', string.Join(',', TSlashMenu.PlaceNames(TSlashMenu.PlacesAt(ProgramText, Spot(3)))));
  // Im Kommentar passt kein Befehl.
  Assert.AreEqual('', string.Join(',', TSlashMenu.PlaceNames(TSlashMenu.PlacesAt(CommentText, Spot(3)))));
end;

procedure TSlashMenuTests.FitsByPlaceAndSelection;
var
  Ctor, Try_, Todo: TSlashMenuEntry;
begin
  Assert.IsTrue(TSlashMenu.Find('ctor', Ctor));
  Assert.IsTrue(TSlashMenu.Find('try', Try_));
  Assert.IsTrue(TSlashMenu.Find('TODO', Todo), 'ohne Groß/Klein');
  Assert.IsTrue(TSlashMenu.Fits(Ctor, [TSlashPlace.ClassBody], False));
  Assert.IsTrue(TSlashMenu.Fits(Ctor, [TSlashPlace.Routine, TSlashPlace.ClassBody], True));
  Assert.IsFalse(TSlashMenu.Fits(Ctor, [TSlashPlace.Routine], False));
  // Umschließen nur mit Markierung in einer Routine.
  Assert.IsFalse(TSlashMenu.Fits(Try_, [TSlashPlace.Routine], False));
  Assert.IsTrue(TSlashMenu.Fits(Try_, [TSlashPlace.Routine], True));
  Assert.IsFalse(TSlashMenu.Fits(Try_, [TSlashPlace.ClassBody], True));
  Assert.IsTrue(TSlashMenu.Fits(Todo, [TSlashPlace.UnitInterface], False));
  Assert.AreEqual('surround', TSlashMenu.GroupName(Try_.Group));
  Assert.AreEqual('optional', TSlashMenu.ArgumentName(Ctor.Argument));
  Assert.IsTrue(Ctor.Multi and Ctor.HasChoices);
  Assert.AreEqual(', ', Ctor.Separator);
  Assert.IsFalse(TSlashMenu.Find('format', Ctor), 'Umbauten stehen nicht im Menü');
end;

procedure TSlashMenuTests.CatalogCommandsAreRegistered;
var
  Item: TSlashMenuEntry;
  Command: TSlashCommand;
  Names: string;
begin
  Names := '';
  for Item in TSlashMenu.Catalog do
  begin
    Assert.IsTrue(TSlashCommandRegistry.Shared.Find(Item.Name, Command), Item.Name);
    Assert.IsTrue(Item.Places <> [], 'Ortsregel: ' + Item.Name);
    Assert.AreEqual(0, Pos(',' + Item.Name + ',', Names), 'doppelt: ' + Item.Name);
    Names := Names + ',' + Item.Name + ',';
  end;
  Assert.AreEqual('ctor', TSlashMenu.Catalog[0].Name, 'Konstruktor zuerst wie im Mockup');
end;

procedure TSlashMenuTests.RunCtorWithoutTyping;
var
  Text, Reason: string;
begin
  Text := RunAt(ClassUnit, Spot(8), 'ctor', '', Reason);
  Assert.AreEqual('', Reason);
  Assert.IsTrue(Pos('constructor Create(const AListe: TStringList; const AName: string);', Text) > 0, Text);
  Assert.IsTrue(Pos('constructor TFoo.Create(const AListe: TStringList; const AName: string);', Text) > 0, Text);
  Assert.AreEqual(0, Pos('/ctor', Text), 'keine Befehlszeile');
  // Die Zeilen der Klasse bleiben unverändert und in der Reihenfolge.
  Assert.IsTrue(Pos('  TFoo = class(TBasis)'#10'  private'#10'    FListe: TStringList;', Text) > 0, Text);
  Assert.IsTrue(Parses(Text), Text);
end;

procedure TSlashMenuTests.RunCtorWithChosenFields;
var
  Text, Reason: string;
begin
  Text := RunAt(ClassUnit, Spot(11), 'ctor', 'FName', Reason);
  Assert.IsTrue(Pos('constructor Create(const AName: string);', Text) > 0, Text);
  Assert.AreEqual(0, Pos('AListe', Text), Text);
  // Ohne F geht auch, mehrere mit Komma.
  Text := RunAt(ClassUnit, Spot(11), 'ctor', 'Name, Liste', Reason);
  Assert.IsTrue(Pos('constructor Create(const AListe: TStringList; const AName: string);', Text) > 0, Text);
  Assert.AreEqual('', RunAt(ClassUnit, Spot(11), 'ctor', 'FGibts', Reason));
  Assert.IsTrue(Pos('kein Feld FGibts in TFoo', Reason) > 0, Reason);
end;

procedure TSlashMenuTests.RunStatementAfterCursorLine;
var
  Text, Reason: string;
begin
  // Cursor in "Schritt1;": /raise kommt dahinter, eingerückt wie die Anweisungen.
  Text := RunAt(ClassUnit, Spot(26), 'raise', 'EFehler Kaputt', Reason);
  Assert.AreEqual('', Reason);
  Assert.IsTrue(Pos('  Schritt1;'#10'  raise EFehler.Create(', Text) > 0, Text);
  Assert.IsTrue(Pos('Kaputt', Text) > 0, Text);
  Assert.IsTrue(Pos(#10'  Schritt2;', Text) > 0, Text);
  Assert.IsTrue(Parses(Text), Text);
end;

procedure TSlashMenuTests.RunSurroundsOnlySelection;
var
  Text, Reason: string;
begin
  // Markierung über Schritt1 und Schritt2: Schritt3 bleibt außerhalb.
  Text := RunAt(ClassUnit, Spot(26, 27), 'ifdef', 'DEBUG', Reason);
  Assert.AreEqual('', Reason);
  Assert.IsTrue(Pos('begin'#10'  {$IFDEF DEBUG}'#10'  Schritt1;'#10'  Schritt2;'#10'  {$ENDIF}'#10'  Schritt3;'#10'end;',
    Text) > 0, Text);
  Text := RunAt(ClassUnit, Spot(27, 27), 'except', '', Reason);
  Assert.IsTrue(Pos('  Schritt1;'#10'  try'#10'    Schritt2;'#10'  except', Text) > 0, Text);
  Assert.IsTrue(Pos('  end;'#10'  Schritt3;'#10'end;', Text) > 0, Text);
  Assert.IsTrue(Parses(Text), Text);
end;

procedure TSlashMenuTests.RunSelectionBeyondBlockFails;
var
  Reason: string;
begin
  // Von Schritt3 bis in die nächste Zeile nach "end;": nicht im selben Block.
  Assert.AreEqual('', RunAt(ClassUnit, Spot(28, 30), 'ifdef', 'DEBUG', Reason));
  Assert.IsTrue(Pos('Markierung', Reason) > 0, Reason);
end;

procedure TSlashMenuTests.RunReportsReason;
var
  Reason: string;
  Edits: TArray<TRuleEdit>;
begin
  Assert.AreEqual('', RunAt(ClassUnit, Spot(26), 'ctor', '', Reason));
  Assert.AreEqual('/ctor gilt nur in einer Klasse oder einer ihrer Methoden', Reason);
  Assert.IsFalse(TSlashMenu.Run(TSlashCommandRegistry.Shared, ClassUnit, Spot(8), 'ctor', '', ['ctor'], nil, '', '',
    nil, Edits, Reason));
  Assert.IsTrue(Pos('abgeschaltet', Reason) > 0, Reason);
  Assert.IsFalse(TSlashMenu.Run(TSlashCommandRegistry.Shared, ClassUnit, Spot(8), 'gibtsnicht', '', nil, nil, '', '',
    nil, Edits, Reason));
  Assert.AreEqual('Unbekannter Schnellbefehl /gibtsnicht', Reason);
end;

procedure TSlashMenuTests.ChoicesForClass;
begin
  Assert.AreEqual('FListe,FName', string.Join(',', TSlashMenu.Choices(ClassUnit, Spot(11), 'ctor', nil)));
  // Lauf überschreibt TFoo schon; Malen bleibt.
  Assert.AreEqual('Malen', string.Join(',', TSlashMenu.Choices(ClassUnit, Spot(11), 'override', nil)));
  // FName hat schon die Property Name.
  Assert.AreEqual('FListe', string.Join(',', TSlashMenu.Choices(ClassUnit, Spot(11), 'encapsulate', nil)));
  Assert.AreEqual('FListe,FName', string.Join(',', TSlashMenu.Choices(ClassUnit, Spot(11), 'equals', nil)));
  // Außerhalb der Klasse keine Felder.
  Assert.AreEqual(0, Integer(Length(TSlashMenu.Choices(ClassUnit, Spot(26), 'ctor', nil))));
end;

procedure TSlashMenuTests.ChoicesStatic;
begin
  Assert.IsTrue(MatchText('WM_SIZE', TSlashMenu.Choices(ClassUnit, Spot(11), 'msg', nil)));
  Assert.IsTrue(MatchText('Implicit', TSlashMenu.Choices(ClassUnit, Spot(11), 'operator', nil)));
  Assert.IsTrue(MatchText('<>', TSlashMenu.Choices(ClassUnit, Spot(11), 'operator', nil)));
  Assert.AreEqual('DEBUG', TSlashMenu.Choices(ClassUnit, Spot(26), 'ifdef', nil)[0]);
  Assert.AreEqual(0, Integer(Length(TSlashMenu.Choices(ClassUnit, Spot(11), 'prop', nil))), 'freie Eingabe');
end;

procedure TSlashMenuTests.MapEditsKeepsIndentAndLineBreak;
var
  Edits: TArray<TRuleEdit>;
begin
  // Gedachter Text: Zeile 1 = "  /x". Ersetzt wird nur "/x": Einrückung und Zeilenende bleiben stehen.
  Edits := TSlashMenu.MapEdits([TRuleEdit.Create(TTextRange.Create(1, 2, 1, 4), 'Neu;')], 1, '  /x', #10);
  Assert.AreEqual(1, Integer(Length(Edits)));
  Assert.AreEqual(1, Edits[0].Range.StartPos.Line);
  Assert.AreEqual(0, Edits[0].Range.StartPos.Character);
  Assert.IsTrue(Edits[0].Range.EndPos = Edits[0].Range.StartPos);
  Assert.AreEqual('  Neu;'#10, Edits[0].NewText);
  // Zeile samt Zeilenende entfernt: entfällt; spätere Zeilen rücken eine Zeile nach oben.
  Edits := TSlashMenu.MapEdits([TRuleEdit.Create(TTextRange.Create(1, 0, 2, 0), ''),
    TRuleEdit.Create(TTextRange.Create(5, 3, 5, 3), 'X')], 1, '  /x', #10);
  Assert.AreEqual(1, Integer(Length(Edits)));
  Assert.AreEqual(4, Edits[0].Range.StartPos.Line);
  Assert.AreEqual(3, Edits[0].Range.StartPos.Character);
  // Davor bleibt alles, wie es ist.
  Edits := TSlashMenu.MapEdits([TRuleEdit.Create(TTextRange.Create(0, 1, 0, 2), 'Y')], 1, '  /x', #10);
  Assert.AreEqual(0, Edits[0].Range.StartPos.Line);
  Assert.AreEqual(1, Edits[0].Range.StartPos.Character);
  Assert.AreEqual('Y', Edits[0].NewText);
end;

initialization
  TDUnitX.RegisterTestFixture(TSlashMenuTests);

end.
