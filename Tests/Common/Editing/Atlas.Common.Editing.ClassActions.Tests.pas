unit Atlas.Common.Editing.ClassActions.Tests;

// Klassen-Aktionen als Code-Aktionen (#42): je Aktion ein Vergleich mit einer
// Golden-Datei, die zugleich mit übersetzt wird, und die Fälle ohne Aktion.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TClassActionsTests = class
  public
    [Test]
    procedure PropertyMatchesGoldenFile;
    [Test]
    procedure InterfaceMatchesGoldenFile;
    [Test]
    procedure OverrideMatchesGoldenFile;
    /// <summary>Property mit read/write, Zeile außerhalb einer Klasse, vollständiges Interface.</summary>
    [Test]
    procedure NoActionsWhereNothingIsMissing;
    [Test]
    procedure PropertyKeepsExistingMembers;
    [Test]
    procedure OverrideOffersOnlyMissingMethods;
    [Test]
    procedure FollowsFormatStyle;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Editing.CodeActions,
  Atlas.Common.Editing.ClassActions;

const
  cPropertyBefore =
    'unit Atlas.Common.Editing.ClassActions.PropertyGolden;'#13#10 +
    #13#10 +
    '// Golden-Datei für die Code-Aktion „Getter, Setter und Feld erzeugen“ (#42):'#13#10 +
    '// genau das, was die Aktion aus "property Name: string;" ohne read/write'#13#10 +
    '// erzeugt. Der Test vergleicht die Ausgabe mit dieser Datei; dass sie'#13#10 +
    '// übersetzt, zeigt der Delphi-Testlauf. Nicht von Hand ändern, sondern neu'#13#10 +
    '// erzeugen.'#13#10 +
    #13#10 +
    'interface'#13#10 +
    #13#10 +
    'type'#13#10 +
    '  TGoldenKunde = class'#13#10 +
    '  public'#13#10 +
    '    constructor Create;'#13#10 +
    '    property Name: string;'#13#10 +
    '  end;'#13#10 +
    #13#10 +
    'implementation'#13#10 +
    #13#10 +
    'constructor TGoldenKunde.Create;'#13#10 +
    'begin'#13#10 +
    '  inherited Create;'#13#10 +
    'end;'#13#10 +
    #13#10 +
    'end.'#13#10;

  cInterfaceBefore =
    'unit Atlas.Common.Editing.ClassActions.InterfaceGolden;'#13#10 +
    #13#10 +
    '// Golden-Datei für die Code-Aktion „Methoden von IFoo implementieren“ (#42):'#13#10 +
    '// genau das, was die Aktion für ein Interface im Kopf der Klasse erzeugt.'#13#10 +
    '// Der Test vergleicht die Ausgabe mit dieser Datei; dass sie übersetzt,'#13#10 +
    '// zeigt der Delphi-Testlauf. Nicht von Hand ändern, sondern neu erzeugen.'#13#10 +
    #13#10 +
    'interface'#13#10 +
    #13#10 +
    'type'#13#10 +
    '  IGoldenZaehler = interface'#13#10 +
    '    [''{6C1D5A3E-7F42-4B8A-9D0E-2A5F8C3B1E47}'']'#13#10 +
    '    function Wert: Integer;'#13#10 +
    '    procedure Erhoehe(ASchritt: Integer);'#13#10 +
    '  end;'#13#10 +
    #13#10 +
    '  TGoldenZaehler = class(TInterfacedObject, IGoldenZaehler)'#13#10 +
    '  end;'#13#10 +
    #13#10 +
    'implementation'#13#10 +
    #13#10 +
    'end.'#13#10;

  cOverrideBefore =
    'unit Atlas.Common.Editing.ClassActions.OverrideGolden; // lsp-ignore-file: override-only-inherited, unused-public-member -- Die Aktion erzeugt absichtlich Rümpfe nur mit inherited; das Testprojekt übersetzt nur das Ergebnis.'#13#10 +
    #13#10 +
    '// Golden-Datei für die Code-Aktion „Name überschreiben“ (#42): genau das,'#13#10 +
    '// was die Aktion für zwei virtuelle Methoden des Vorfahren erzeugt. Der Test'#13#10 +
    '// vergleicht die Ausgabe mit dieser Datei; dass sie übersetzt, zeigt der'#13#10 +
    '// Delphi-Testlauf. Nicht von Hand ändern, sondern neu erzeugen.'#13#10 +
    #13#10 +
    'interface'#13#10 +
    #13#10 +
    'type'#13#10 +
    '  TGoldenBasis = class'#13#10 +
    '  public'#13#10 +
    '    procedure Zeichne; virtual;'#13#10 +
    '    function Beschreibung(AKurz: Boolean): string; virtual;'#13#10 +
    '  end;'#13#10 +
    #13#10 +
    '  TGoldenFigur = class(TGoldenBasis)'#13#10 +
    '  end;'#13#10 +
    #13#10 +
    'implementation'#13#10 +
    #13#10 +
    'procedure TGoldenBasis.Zeichne;'#13#10 +
    'begin'#13#10 +
    'end;'#13#10 +
    #13#10 +
    'function TGoldenBasis.Beschreibung(AKurz: Boolean): string;'#13#10 +
    'begin'#13#10 +
    '  Result := '''';'#13#10 +
    '  if AKurz then'#13#10 +
    '  begin'#13#10 +
    '    Result := ''Basis'';'#13#10 +
    '  end;'#13#10 +
    'end;'#13#10 +
    #13#10 +
    'end.'#13#10;

/// <summary>Wendet AEdits an; sie dürfen sich nicht überlappen.</summary>
function ApplyEdits(const AText: string; const AEdits: TArray<TTextEdit>): string;
var
  mLines: TArray<string>;
  mOrder: TArray<Integer>;
  mIndex, mInner, mSwap, mStart, mStop: Integer;

  function OffsetOf(const APos: TTextPosition): Integer;
  var
    mLine: Integer;
  begin
    Result := 0;
    for mLine := 0 to APos.Line - 1 do
    begin
      Inc(Result, Length(mLines[mLine]) + 1);
    end;
    Inc(Result, APos.Character);
  end;

  function Before(A, B: Integer): Boolean;
  begin
    Result := OffsetOf(AEdits[A].Range.StartPos) < OffsetOf(AEdits[B].Range.StartPos);
  end;

begin
  mLines := AText.Split([#10]);
  // Von hinten anwenden; gleiche Stelle in der gegebenen Reihenfolge.
  SetLength(mOrder, Length(AEdits));
  for mIndex := 0 to High(mOrder) do
  begin
    mOrder[mIndex] := mIndex;
  end;
  for mIndex := 0 to High(mOrder) do
  begin
    for mInner := mIndex + 1 to High(mOrder) do
    begin
      if Before(mOrder[mIndex], mOrder[mInner]) or
        ((OffsetOf(AEdits[mOrder[mIndex]].Range.StartPos) = OffsetOf(AEdits[mOrder[mInner]].Range.StartPos)) and
        (mOrder[mIndex] < mOrder[mInner])) then
      begin
        mSwap := mOrder[mIndex];
        mOrder[mIndex] := mOrder[mInner];
        mOrder[mInner] := mSwap;
      end;
    end;
  end;
  Result := AText;
  for mIndex in mOrder do
  begin
    mStart := OffsetOf(AEdits[mIndex].Range.StartPos);
    mStop := OffsetOf(AEdits[mIndex].Range.EndPos);
    Result := Copy(Result, 1, mStart) + AEdits[mIndex].NewText + Copy(Result, mStop + 1, MaxInt);
  end;
end;

function SyntaxErrors(const AText: string): Integer;
var
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(AText);
  try
    Result := Length(mTree.Diagnostics);
  finally
    mTree.Free;
  end;
end;

/// <summary>Datei unter Tests/ ab dem Programmordner bzw. dem aktuellen Ordner aufwärts; '' ohne.</summary>
function TestsFile(const ARelative: string): string;
var
  mStarts: TArray<string>;
  mStart, mDirectory: string;
begin
  mStarts := [ExtractFileDir(ParamStr(0)), GetCurrentDir];
  for mStart in mStarts do
  begin
    mDirectory := mStart;
    while mDirectory <> '' do
    begin
      Result := TPath.Combine(mDirectory, TPath.Combine('Tests', ARelative));
      if TFile.Exists(Result) then
      begin
        Exit;
      end;
      if ExtractFileDir(mDirectory) = mDirectory then
      begin
        Break;
      end;
      mDirectory := ExtractFileDir(mDirectory);
    end;
  end;
  Result := '';
end;

function Golden(const AName: string): string;
var
  mFileName: string;
begin
  mFileName := TestsFile(TPath.Combine('Common', TPath.Combine('Editing', AName + '.pas')));
  Assert.AreNotEqual('', mFileName, 'Golden-Datei nicht gefunden: ' + AName);
  Result := TFile.ReadAllText(mFileName, TEncoding.UTF8);
  if (Result <> '') and (Result[1] = #$FEFF) then
  begin
    Delete(Result, 1, 1);
  end;
end;

/// <summary>Titel aller Aktionen für ALine.</summary>
function Titles(const AText: string; ALine: Integer): string;
var
  mTree: TSyntaxTree;
  mAction: TCodeAction;
begin
  Result := '';
  mTree := TPascalParser.Parse(AText);
  try
    for mAction in TClassActions.Actions(AText, mTree, ALine, TClassActionContext.Default) do
    begin
      Result := Result + mAction.Title + '|';
    end;
  finally
    mTree.Free;
  end;
end;

{ TClassActionsTests }

procedure TClassActionsTests.PropertyMatchesGoldenFile;
var
  mAction: TCodeAction;
  mText: string;
begin
  Assert.IsTrue(TClassActions.PropertyAccessors(cPropertyBefore, 14, TClassActionContext.Default, mAction));
  Assert.AreEqual('Getter, Setter und Feld für Name erzeugen', mAction.Title);
  mText := ApplyEdits(cPropertyBefore, mAction.Edits);
  Assert.AreEqual(Golden('Atlas.Common.Editing.ClassActions.PropertyGolden'), mText);
  Assert.AreEqual(0, SyntaxErrors(mText));
end;

procedure TClassActionsTests.InterfaceMatchesGoldenFile;
var
  mAction: TCodeAction;
  mText: string;
begin
  Assert.IsTrue(TClassActions.ImplementInterface(cInterfaceBefore, 16, 'IGoldenZaehler', TClassActionContext.Default,
    mAction));
  Assert.AreEqual('Methoden von IGoldenZaehler implementieren', mAction.Title);
  mText := ApplyEdits(cInterfaceBefore, mAction.Edits);
  Assert.AreEqual(Golden('Atlas.Common.Editing.ClassActions.InterfaceGolden'), mText);
  Assert.AreEqual(0, SyntaxErrors(mText));
  // Danach ist nichts mehr zu implementieren.
  Assert.IsFalse(TClassActions.ImplementInterface(mText, 16, 'IGoldenZaehler', TClassActionContext.Default, mAction));
end;

procedure TClassActionsTests.OverrideMatchesGoldenFile;
var
  mAction: TCodeAction;
  mText: string;
begin
  Assert.AreEqual('Zeichne,Beschreibung', string.Join(',',
    TClassActions.OverrideCandidates(cOverrideBefore, 16, TClassActionContext.Default)));
  Assert.IsTrue(TClassActions.OverrideMethod(cOverrideBefore, 16, 'Zeichne', TClassActionContext.Default, mAction));
  Assert.AreEqual('Zeichne überschreiben', mAction.Title);
  mText := ApplyEdits(cOverrideBefore, mAction.Edits);
  Assert.IsTrue(TClassActions.OverrideMethod(mText, 16, 'Beschreibung', TClassActionContext.Default, mAction));
  mText := ApplyEdits(mText, mAction.Edits);
  Assert.AreEqual(Golden('Atlas.Common.Editing.ClassActions.OverrideGolden'), mText);
  Assert.AreEqual(0, SyntaxErrors(mText));
  Assert.AreEqual('', string.Join(',', TClassActions.OverrideCandidates(mText, 16, TClassActionContext.Default)));
end;

procedure TClassActionsTests.NoActionsWhereNothingIsMissing;
var
  mAction: TCodeAction;
  mText: string;
begin
  // Außerhalb einer Klasse: nichts.
  Assert.AreEqual('', Titles(cOverrideBefore, 22));
  Assert.AreEqual('', Titles(cInterfaceBefore, 11));
  // Property mit read/write: kein Getter/Setter.
  mText := StringReplace(cPropertyBefore, 'property Name: string;', 'property Name: string read FName;',
    [rfReplaceAll]);
  Assert.IsFalse(TClassActions.PropertyAccessors(mText, 14, TClassActionContext.Default, mAction));
  Assert.AreEqual(0, Pos('Getter', Titles(mText, 14)));
  // Klasse ohne Vorfahren mit virtuellen Methoden und ohne Interface.
  Assert.AreEqual('', Titles(cOverrideBefore, 11));
end;

procedure TClassActionsTests.PropertyKeepsExistingMembers;
var
  mAction: TCodeAction;
  mText: string;
begin
  // Feld und Getter gibt es schon: nur der Setter kommt dazu.
  mText := StringReplace(cPropertyBefore, '  public'#13#10'    constructor Create;',
    '  private'#13#10'    FName: string;'#13#10'    function GetName: string;'#13#10'  public'#13#10 +
    '    constructor Create;', []);
  Assert.IsTrue(TClassActions.PropertyAccessors(mText, 17, TClassActionContext.Default, mAction));
  mText := ApplyEdits(mText, mAction.Edits);
  Assert.AreEqual(1, Integer(Length(mText.Split(['FName: string;'])) - 1), mText);
  Assert.AreEqual(1, Integer(Length(mText.Split(['function GetName: string;'])) - 1), mText);
  Assert.IsTrue(Pos('    procedure SetName(const Value: string);', mText) > 0, mText);
  Assert.IsTrue(Pos('property Name: string read GetName write SetName;', mText) > 0, mText);
end;

procedure TClassActionsTests.OverrideOffersOnlyMissingMethods;
var
  mTitled: string;
begin
  mTitled := Titles(cOverrideBefore, 16);
  Assert.IsTrue(Pos('Zeichne überschreiben|', mTitled) > 0, mTitled);
  Assert.IsTrue(Pos('Beschreibung überschreiben|', mTitled) > 0, mTitled);
  mTitled := Titles(StringReplace(cOverrideBefore, '  TGoldenFigur = class(TGoldenBasis)'#13#10,
    '  TGoldenFigur = class(TGoldenBasis)'#13#10'    procedure Zeichne; override;'#13#10, []), 16);
  Assert.AreEqual(0, Pos('Zeichne überschreiben', mTitled), mTitled);
  Assert.IsTrue(Pos('Beschreibung überschreiben|', mTitled) > 0, mTitled);
end;

procedure TClassActionsTests.FollowsFormatStyle;
var
  mContext: TClassActionContext;
  mAction: TCodeAction;
  mText: string;
begin
  mContext := TClassActionContext.Default;
  mContext.Style.IndentSize := 4;
  Assert.IsTrue(TClassActions.PropertyAccessors(cPropertyBefore, 14, mContext, mAction));
  mText := ApplyEdits(cPropertyBefore, mAction.Edits);
  Assert.IsTrue(Pos('function TGoldenKunde.GetName: string;'#13#10'begin'#13#10'    Result := FName;', mText) > 0,
    mText);
end;

initialization
  TDUnitX.RegisterTestFixture(TClassActionsTests);

end.
