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
  Atlas.Common.Editing.Contract,
  Atlas.Common.Editing.CollectionCommands;

function Run(const AText: string; ALine: Integer; out AEdits: TArray<TRuleEdit>): Boolean;
begin
  Result := TSlashCommandRegistry.Shared.AfterEnter(AText, TTextPosition.Create(ALine + 1, 0), nil, nil, AEdits);
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
  TArray.Sort<TRuleEdit>(AEdits, TComparer<TRuleEdit>.Construct(
    function(const ALeft, ARight: TRuleEdit): Integer
    begin
      Result := (ARight.Range.StartPos.Line - ALeft.Range.StartPos.Line) * 100000 +
        ARight.Range.StartPos.Character - ALeft.Range.StartPos.Character;
    end));
  Result := AText;
  for mEdit in AEdits do
  begin
    mStart := mOffsets[mEdit.Range.StartPos.Line] + mEdit.Range.StartPos.Character;
    mStop := mOffsets[mEdit.Range.EndPos.Line] + mEdit.Range.EndPos.Character;
    Result := Copy(Result, 1, mStart) + mEdit.NewText + Copy(Result, mStop + 1, MaxInt);
  end;
end;

function Expand(const AText: string; ALine: Integer): string;
var
  mEdits: TArray<TRuleEdit>;
begin
  Assert.IsTrue(Run(AText, ALine, mEdits), AText);
  Result := Apply(AText, mEdits);
end;

function ProblemOf(const AText: string): string;
var
  mProblems: TArray<TSlashProblem>;
begin
  mProblems := TSlashCommandRegistry.Shared.Problems(AText, nil);
  Assert.AreEqual(1, Integer(Length(mProblems)));
  Result := mProblems[0].Message;
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

const
  cClassUnit =
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

  cWithMethods =
    'constructor TVerwaltung.Create;'#10 +
    'begin'#10 +
    '  inherited Create;'#10 +
    'end;'#10 +
    #10 +
    'destructor TVerwaltung.Destroy;'#10 +
    'begin'#10 +
    '  inherited;'#10 +
    'end;';

  cRoutineUnit =
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

function InClass(const ACommand: string; const AMethods: string): string; overload;
begin
  Result := Expand(Format(cClassUnit, [ACommand, AMethods]), 14);
end;

function InClass(const ACommand: string): string; overload;
begin
  Result := InClass(ACommand, '');
end;

function InRoutine(const ACommand: string): string;
begin
  Result := Expand(Format(cRoutineUnit, [ACommand]), 14);
end;

procedure TCollectionCommandsTests.ListInClassAddsFieldConstructorDestructor;
var
  mText: string;
begin
  mText := InClass('/list FKunden: TKunde');
  Assert.Contains(mText, '    FKunden: TObjectList<TKunde>;');
  Assert.Contains(mText, '    constructor Create;');
  Assert.Contains(mText, '    destructor Destroy; override;');
  Assert.Contains(mText, '  FKunden := TObjectList<TKunde>.Create;');
  Assert.Contains(mText, '  FKunden.Free;'#10'  inherited;');
  Assert.Contains(mText, 'System.Classes,'#10'  System.Generics.Collections;');
  Assert.IsFalse(mText.Contains('/list'), mText);
  Assert.IsTrue(Parses(mText), mText);
end;

procedure TCollectionCommandsTests.ListUsesExistingConstructorAndDestructor;
var
  mText: string;
begin
  mText := InClass('/list FKunden: TKunde', cWithMethods);
  Assert.Contains(mText, '  inherited Create;'#10'  FKunden := TObjectList<TKunde>.Create;');
  Assert.Contains(mText, '  FKunden.Free;'#10'  inherited;');
  Assert.IsFalse(mText.Contains('constructor Create;'#10), mText);
  Assert.IsTrue(Parses(mText), mText);
end;

procedure TCollectionCommandsTests.ListOfSimpleTypeIsTList;
begin
  Assert.Contains(InClass('/list FZahlen: Integer'), 'FZahlen: TList<Integer>;');
end;

procedure TCollectionCommandsTests.ListInRoutineIsLocalWithTry;
var
  mText: string;
begin
  mText := InRoutine('/list Treffer: TKunde');
  Assert.Contains(mText, 'var'#10'  Treffer: TObjectList<TKunde>;'#10'begin');
  Assert.Contains(mText, '  Treffer := TObjectList<TKunde>.Create;'#10'  try'#10'    Writeln(1);'#10'  finally'#10 +
    '    Treffer.Free;'#10'  end;');
  Assert.IsTrue(Parses(mText), mText);
end;

procedure TCollectionCommandsTests.DictOwnsClassValues;
var
  mText: string;
begin
  mText := InClass('/dict FCache: string, TKunde');
  Assert.Contains(mText, 'FCache: TObjectDictionary<string, TKunde>;');
  Assert.Contains(mText, 'FCache := TObjectDictionary<string, TKunde>.Create([doOwnsValues]);');
  Assert.Contains(InClass('/dict FAlter: string, Integer'), 'FAlter := TDictionary<string, Integer>.Create;');
end;

procedure TCollectionCommandsTests.DictIgnoreCaseUsesComparer;
var
  mText: string;
begin
  mText := InClass('/dict! FCache: string, Integer');
  Assert.Contains(mText, 'FCache := TDictionary<string, Integer>.Create(TIStringComparer.Ordinal);');
  Assert.Contains(mText, 'System.Generics.Collections,'#10'  System.Generics.Defaults;');
  Assert.IsTrue(Parses(mText), mText);
end;

procedure TCollectionCommandsTests.DictIgnoreCaseNeedsStringKey;
begin
  Assert.AreEqual('/dict! braucht einen String als Schlüssel',
    ProblemOf(Format(cClassUnit, ['/dict! FCache: Integer, string', ''])));
end;

procedure TCollectionCommandsTests.SortByStringAndDescendingNumber;
var
  mText: string;
begin
  mText := InRoutine('/sort Kunden Name');
  Assert.Contains(mText, '  Kunden.Sort(TComparer<TKunde>.Construct('#10 +
    '    function(const L, R: TKunde): Integer'#10'    begin'#10'      Result := CompareText(L.Name, R.Name);'#10 +
    '    end));'#10'  Writeln(1);');
  Assert.Contains(mText, 'System.Generics.Collections,'#10'  System.Generics.Defaults;');
  Assert.IsTrue(Parses(mText), mText);
  mText := InRoutine('/sort Kunden -Umsatz');
  Assert.Contains(mText, 'Result := CompareValue(R.Umsatz, L.Umsatz);');
  Assert.Contains(mText, 'System.Generics.Defaults,'#10'  System.Math;');
end;

procedure TCollectionCommandsTests.SortUnknownMemberFails;
begin
  Assert.AreEqual('TKunde hat kein Feld oder keine Property Ort',
    ProblemOf(Format(cRoutineUnit, ['/sort Kunden Ort'])));
  Assert.AreEqual('Elementtyp von Liste nicht erkannt', ProblemOf(Format(cRoutineUnit, ['/sort Liste Name'])));
end;

procedure TCollectionCommandsTests.FilterCollectsMatches;
var
  mText: string;
begin
  mText := InRoutine('/filter Kunden Aktiv and (Umsatz > 0)');
  Assert.Contains(mText, '  var Treffer := TList<TKunde>.Create;'#10'  try'#10'    for var K in Kunden do'#10 +
    '      if K.Aktiv and (K.Umsatz > 0) then'#10'        Treffer.Add(K);');
  Assert.Contains(InRoutine('/filter Kunden not Aktiv'), 'if not K.Aktiv then');
  // Nur Mitglieder des Elementtyps, nicht Funktionen, Konstanten oder Mitglieder dahinter.
  Assert.Contains(InRoutine('/filter Kunden (Umsatz > Grenze) or SameText(Name, K.Name)'),
    'if (K.Umsatz > Grenze) or SameText(K.Name, K.Name) then');
end;

procedure TCollectionCommandsTests.FilterWithoutInlineVariables;
var
  mEdits: TArray<TRuleEdit>;
  mText: string;
begin
  // Delphi 10.2 (BDS 19.0) kennt keine Inline-Variablen (#109): beide in den var-Abschnitt.
  Assert.IsTrue(TSlashCommandRegistry.Shared.AfterEnter(Format(cRoutineUnit, ['/filter Kunden Aktiv']),
    TTextPosition.Create(15, 0), TSlashEnvironment.Create(nil, nil, nil, '19.0', '', nil), mEdits));
  mText := Apply(Format(cRoutineUnit, ['/filter Kunden Aktiv']), mEdits);
  Assert.IsTrue(Parses(mText), mText);
  Assert.Contains(mText, 'procedure P(Kunden: TList<TKunde>);'#10'var'#10'  Treffer: TList<TKunde>;'#10 +
    '  K: TKunde;'#10'begin'#10);
  Assert.Contains(mText, '  Treffer := TList<TKunde>.Create;'#10'  try'#10'    for K in Kunden do'#10);
  Assert.DoesNotContain(mText, 'var Treffer');
end;

procedure TCollectionCommandsTests.WrongPlaceFails;
const
  cUnitLevel = 'unit U;'#10'interface'#10'%s'#10'implementation'#10'end.';
begin
  Assert.AreEqual('/dict gilt nur in einer Klasse oder im Rumpf einer Routine',
    ProblemOf(Format(cUnitLevel, ['/dict FCache: string, Integer'])));
  Assert.AreEqual('/sort gilt nur im Rumpf einer Routine', ProblemOf(Format(cClassUnit, ['/sort FListe Name', ''])));
  Assert.AreEqual('/filter gilt nur im Rumpf einer Routine',
    ProblemOf(Format(cClassUnit, ['/filter FListe Aktiv', ''])));
end;

procedure TCollectionCommandsTests.ChoicesForSortAndFilter;
var
  mContext: TSlashContext;
  mText: string;
begin
  // Erst die Sammlungen im Gültigkeitsbereich, dann Felder und Properties des Elementtyps.
  mText := Format(cRoutineUnit, ['/sort ']);
  mContext := Default(TSlashContext);
  mContext.Text := mText;
  mContext.Line := 14;
  Assert.AreEqual('Kunden', string.Join(',', CollectionChoices(mContext, '')));
  Assert.AreEqual('Name,Umsatz,Aktiv', string.Join(',', CollectionChoices(mContext, 'Kunden')));
  Assert.AreEqual(0, Integer(Length(CollectionChoices(mContext, 'Unbekannt'))));
end;

procedure TCollectionCommandsTests.CompareFunctionByType;
var
  mUnitName: string;
begin
  Assert.AreEqual('CompareText(%s, %s)', CompareFunction('string', mUnitName));
  Assert.AreEqual('', mUnitName);
  Assert.AreEqual('CompareDateTime(%s, %s)', CompareFunction('TDateTime', mUnitName));
  Assert.AreEqual('System.DateUtils', mUnitName);
  Assert.AreEqual('CompareValue(%s, %s)', CompareFunction('Int64', mUnitName));
  Assert.AreEqual('System.Math', mUnitName);
  Assert.AreEqual('Ord(%s) - Ord(%s)', CompareFunction('Boolean', mUnitName));
end;

procedure TCollectionCommandsTests.OutsideClassAndRoutineFails;
const
  cText = 'unit U;'#10'interface'#10'/list FX: Integer'#10'implementation'#10'end.';
begin
  Assert.AreEqual('/list gilt nur in einer Klasse oder im Rumpf einer Routine', ProblemOf(cText));
end;

initialization
  TDUnitX.RegisterTestFixture(TCollectionCommandsTests);

end.
