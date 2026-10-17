unit Atlas.Common.Editing.CollectionCommands.Tests;

// Tests für die Schnellbefehle /list, /dict, /dict!, /sort und /filter (#319).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TCollectionCommandsTests = class
  public
    [Test]
    procedure ListInClassAddsFieldConstructorDestructor;
    [Test]
    procedure ListUsesExistingConstructorAndDestructor;
    [Test]
    procedure ListOfSimpleTypeIsTList;
    [Test]
    procedure ListInRoutineIsLocalWithTry;
    [Test]
    procedure DictOwnsClassValues;
    [Test]
    procedure DictIgnoreCaseUsesComparer;
    [Test]
    procedure DictIgnoreCaseNeedsStringKey;
    [Test]
    procedure SortByStringAndDescendingNumber;
    [Test]
    procedure SortUnknownMemberFails;
    [Test]
    procedure FilterCollectsMatches;
    [Test]
    procedure FilterWithoutInlineVariables;
    [Test]
    procedure WrongPlaceFails;
    [Test]
    procedure ChoicesForSortAndFilter;
    [Test]
    procedure CompareFunctionByType;
    [Test]
    procedure OutsideClassAndRoutineFails;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  System.Generics.Defaults,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Editing.SlashCommands,
  Atlas.Common.Editing.CollectionCommands;

function Run(const AText: string; ALine: Integer; out AEdits: TArray<TRuleEdit>): Boolean;
begin
  Result := TSlashCommandRegistry.Shared.AfterEnter(AText, TTextPosition.Create(ALine + 1, 0), nil, nil, AEdits);
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
  TArray.Sort<TRuleEdit>(AEdits, TComparer<TRuleEdit>.Construct(
    function(const ALeft, ARight: TRuleEdit): Integer
    begin
      Result := (ARight.Range.StartPos.Line - ALeft.Range.StartPos.Line) * 100000 +
        ARight.Range.StartPos.Character - ALeft.Range.StartPos.Character;
    end));
  Result := AText;
  for Edit in AEdits do
  begin
    Start := Offsets[Edit.Range.StartPos.Line] + Edit.Range.StartPos.Character;
    Stop := Offsets[Edit.Range.EndPos.Line] + Edit.Range.EndPos.Character;
    Result := Copy(Result, 1, Start) + Edit.NewText + Copy(Result, Stop + 1, MaxInt);
  end;
end;

function Expand(const AText: string; ALine: Integer): string;
var
  Edits: TArray<TRuleEdit>;
begin
  Assert.IsTrue(Run(AText, ALine, Edits), AText);
  Result := Apply(AText, Edits);
end;

function ProblemOf(const AText: string): string;
var
  Problems: TArray<TSlashProblem>;
begin
  Problems := TSlashCommandRegistry.Shared.Problems(AText, nil);
  Assert.AreEqual(1, Integer(Length(Problems)));
  Result := Problems[0].Message;
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

const
  ClassUnit =
    'unit U;'#10 +                                  // 0
    'interface'#10 +                                // 1
    'uses'#10 +                                     // 2
    '  System.Classes;'#10 +                        // 3
    'type'#10 +                                     // 4
    '  TKunde = class'#10 +                         // 5
    '  public'#10 +                                 // 6
    '    Name: string;'#10 +                        // 7
    '    Umsatz: Double;'#10 +                      // 8
    '    Aktiv: Boolean;'#10 +                      // 9
    '  end;'#10 +                                   // 10
    '  TVerwaltung = class'#10 +                    // 11
    '  private'#10 +                                // 12
    '    FName: string;'#10 +                       // 13
    '    %s'#10 +                                   // 14 Befehl
    '  end;'#10 +                                   // 15
    'implementation'#10 +                           // 16
    '%s'#10 +                                       // 17
    'end.';

  WithMethods =
    'constructor TVerwaltung.Create;'#10 +
    'begin'#10 +
    '  inherited Create;'#10 +
    'end;'#10 +
    #10 +
    'destructor TVerwaltung.Destroy;'#10 +
    'begin'#10 +
    '  inherited;'#10 +
    'end;';

  RoutineUnit =
    'unit U;'#10 +                                  // 0
    'interface'#10 +                                // 1
    'type'#10 +                                     // 2
    '  TKunde = class'#10 +                         // 3
    '  public'#10 +                                 // 4
    '    Name: string;'#10 +                        // 5
    '    Umsatz: Double;'#10 +                      // 6
    '    Aktiv: Boolean;'#10 +                      // 7
    '  end;'#10 +                                   // 8
    'implementation'#10 +                           // 9
    'uses'#10 +                                     // 10
    '  System.Generics.Collections;'#10 +           // 11
    'procedure P(Kunden: TList<TKunde>);'#10 +      // 12
    'begin'#10 +                                    // 13
    '  %s'#10 +                                     // 14 Befehl
    '  Writeln(1);'#10 +                            // 15
    'end;'#10 +                                     // 16
    'end.';

function InClass(const ACommand: string; const AMethods: string = ''): string;
begin
  Result := Expand(Format(ClassUnit, [ACommand, AMethods]), 14);
end;

function InRoutine(const ACommand: string): string;
begin
  Result := Expand(Format(RoutineUnit, [ACommand]), 14);
end;

procedure TCollectionCommandsTests.ListInClassAddsFieldConstructorDestructor;
var
  Text: string;
begin
  Text := InClass('/list FKunden: TKunde');
  Assert.Contains(Text, '    FKunden: TObjectList<TKunde>;');
  Assert.Contains(Text, '    constructor Create;');
  Assert.Contains(Text, '    destructor Destroy; override;');
  Assert.Contains(Text, '  FKunden := TObjectList<TKunde>.Create;');
  Assert.Contains(Text, '  FKunden.Free;'#10'  inherited;');
  Assert.Contains(Text, 'System.Classes,'#10'  System.Generics.Collections;');
  Assert.IsFalse(Text.Contains('/list'), Text);
  Assert.IsTrue(Parses(Text), Text);
end;

procedure TCollectionCommandsTests.ListUsesExistingConstructorAndDestructor;
var
  Text: string;
begin
  Text := InClass('/list FKunden: TKunde', WithMethods);
  Assert.Contains(Text, '  inherited Create;'#10'  FKunden := TObjectList<TKunde>.Create;');
  Assert.Contains(Text, '  FKunden.Free;'#10'  inherited;');
  Assert.IsFalse(Text.Contains('constructor Create;'#10), Text);
  Assert.IsTrue(Parses(Text), Text);
end;

procedure TCollectionCommandsTests.ListOfSimpleTypeIsTList;
begin
  Assert.Contains(InClass('/list FZahlen: Integer'), 'FZahlen: TList<Integer>;');
end;

procedure TCollectionCommandsTests.ListInRoutineIsLocalWithTry;
var
  Text: string;
begin
  Text := InRoutine('/list Treffer: TKunde');
  Assert.Contains(Text, 'var'#10'  Treffer: TObjectList<TKunde>;'#10'begin');
  Assert.Contains(Text, '  Treffer := TObjectList<TKunde>.Create;'#10'  try'#10'    Writeln(1);'#10'  finally'#10 +
    '    Treffer.Free;'#10'  end;');
  Assert.IsTrue(Parses(Text), Text);
end;

procedure TCollectionCommandsTests.DictOwnsClassValues;
var
  Text: string;
begin
  Text := InClass('/dict FCache: string, TKunde');
  Assert.Contains(Text, 'FCache: TObjectDictionary<string, TKunde>;');
  Assert.Contains(Text, 'FCache := TObjectDictionary<string, TKunde>.Create([doOwnsValues]);');
  Assert.Contains(InClass('/dict FAlter: string, Integer'), 'FAlter := TDictionary<string, Integer>.Create;');
end;

procedure TCollectionCommandsTests.DictIgnoreCaseUsesComparer;
var
  Text: string;
begin
  Text := InClass('/dict! FCache: string, Integer');
  Assert.Contains(Text, 'FCache := TDictionary<string, Integer>.Create(TIStringComparer.Ordinal);');
  Assert.Contains(Text, 'System.Generics.Collections,'#10'  System.Generics.Defaults;');
  Assert.IsTrue(Parses(Text), Text);
end;

procedure TCollectionCommandsTests.DictIgnoreCaseNeedsStringKey;
begin
  Assert.AreEqual('/dict! braucht einen String als Schlüssel',
    ProblemOf(Format(ClassUnit, ['/dict! FCache: Integer, string', ''])));
end;

procedure TCollectionCommandsTests.SortByStringAndDescendingNumber;
var
  Text: string;
begin
  Text := InRoutine('/sort Kunden Name');
  Assert.Contains(Text, '  Kunden.Sort(TComparer<TKunde>.Construct('#10 +
    '    function(const L, R: TKunde): Integer'#10'    begin'#10'      Result := CompareText(L.Name, R.Name);'#10 +
    '    end));'#10'  Writeln(1);');
  Assert.Contains(Text, 'System.Generics.Collections,'#10'  System.Generics.Defaults;');
  Assert.IsTrue(Parses(Text), Text);
  Text := InRoutine('/sort Kunden -Umsatz');
  Assert.Contains(Text, 'Result := CompareValue(R.Umsatz, L.Umsatz);');
  Assert.Contains(Text, 'System.Generics.Defaults,'#10'  System.Math;');
end;

procedure TCollectionCommandsTests.SortUnknownMemberFails;
begin
  Assert.AreEqual('TKunde hat kein Feld oder keine Property Ort',
    ProblemOf(Format(RoutineUnit, ['/sort Kunden Ort'])));
  Assert.AreEqual('Elementtyp von Liste nicht erkannt', ProblemOf(Format(RoutineUnit, ['/sort Liste Name'])));
end;

procedure TCollectionCommandsTests.FilterCollectsMatches;
var
  Text: string;
begin
  Text := InRoutine('/filter Kunden Aktiv and (Umsatz > 0)');
  Assert.Contains(Text, '  var Treffer := TList<TKunde>.Create;'#10'  try'#10'    for var K in Kunden do'#10 +
    '      if K.Aktiv and (K.Umsatz > 0) then'#10'        Treffer.Add(K);');
  Assert.Contains(InRoutine('/filter Kunden not Aktiv'), 'if not K.Aktiv then');
  // Nur Mitglieder des Elementtyps, nicht Funktionen, Konstanten oder Mitglieder dahinter.
  Assert.Contains(InRoutine('/filter Kunden (Umsatz > Grenze) or SameText(Name, K.Name)'),
    'if (K.Umsatz > Grenze) or SameText(K.Name, K.Name) then');
end;

procedure TCollectionCommandsTests.FilterWithoutInlineVariables;
var
  Edits: TArray<TRuleEdit>;
  Text: string;
begin
  // Delphi 10.2 (BDS 19.0) kennt keine Inline-Variablen (#109): beide in den var-Abschnitt.
  Assert.IsTrue(TSlashCommandRegistry.Shared.AfterEnter(Format(RoutineUnit, ['/filter Kunden Aktiv']),
    TTextPosition.Create(15, 0), nil, nil, Edits, nil, '19.0'));
  Text := Apply(Format(RoutineUnit, ['/filter Kunden Aktiv']), Edits);
  Assert.IsTrue(Parses(Text), Text);
  Assert.Contains(Text, 'procedure P(Kunden: TList<TKunde>);'#10'var'#10'  Treffer: TList<TKunde>;'#10 +
    '  K: TKunde;'#10'begin'#10);
  Assert.Contains(Text, '  Treffer := TList<TKunde>.Create;'#10'  try'#10'    for K in Kunden do'#10);
  Assert.DoesNotContain(Text, 'var Treffer');
end;

procedure TCollectionCommandsTests.WrongPlaceFails;
const
  UnitLevel = 'unit U;'#10'interface'#10'%s'#10'implementation'#10'end.';
begin
  Assert.AreEqual('/dict gilt nur in einer Klasse oder im Rumpf einer Routine',
    ProblemOf(Format(UnitLevel, ['/dict FCache: string, Integer'])));
  Assert.AreEqual('/sort gilt nur im Rumpf einer Routine', ProblemOf(Format(ClassUnit, ['/sort FListe Name', ''])));
  Assert.AreEqual('/filter gilt nur im Rumpf einer Routine',
    ProblemOf(Format(ClassUnit, ['/filter FListe Aktiv', ''])));
end;

procedure TCollectionCommandsTests.ChoicesForSortAndFilter;
var
  Context: TSlashContext;
  Text: string;
begin
  // Erst die Sammlungen im Gültigkeitsbereich, dann Felder und Properties des Elementtyps.
  Text := Format(RoutineUnit, ['/sort ']);
  Context := Default(TSlashContext);
  Context.Text := Text;
  Context.Line := 14;
  Assert.AreEqual('Kunden', string.Join(',', CollectionChoices(Context, '')));
  Assert.AreEqual('Name,Umsatz,Aktiv', string.Join(',', CollectionChoices(Context, 'Kunden')));
  Assert.AreEqual(0, Integer(Length(CollectionChoices(Context, 'Unbekannt'))));
end;

procedure TCollectionCommandsTests.CompareFunctionByType;
var
  UnitName: string;
begin
  Assert.AreEqual('CompareText(%s, %s)', CompareFunction('string', UnitName));
  Assert.AreEqual('', UnitName);
  Assert.AreEqual('CompareDateTime(%s, %s)', CompareFunction('TDateTime', UnitName));
  Assert.AreEqual('System.DateUtils', UnitName);
  Assert.AreEqual('CompareValue(%s, %s)', CompareFunction('Int64', UnitName));
  Assert.AreEqual('System.Math', UnitName);
  Assert.AreEqual('Ord(%s) - Ord(%s)', CompareFunction('Boolean', UnitName));
end;

procedure TCollectionCommandsTests.OutsideClassAndRoutineFails;
const
  Text = 'unit U;'#10'interface'#10'/list FX: Integer'#10'implementation'#10'end.';
begin
  Assert.AreEqual('/list gilt nur in einer Klasse oder im Rumpf einer Routine', ProblemOf(Text));
end;

initialization
  TDUnitX.RegisterTestFixture(TCollectionCommandsTests);

end.
