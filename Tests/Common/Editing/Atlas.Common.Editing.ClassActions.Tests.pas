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
  PropertyBefore =
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

  InterfaceBefore =
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

  OverrideBefore =
    'unit Atlas.Common.Editing.ClassActions.OverrideGolden; // lsp-ignore-file: override-only-inherited -- Die Aktion erzeugt absichtlich Rümpfe nur mit inherited.'#13#10 +
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
    '    Result := ''Basis'';'#13#10 +
    'end;'#13#10 +
    #13#10 +
    'end.'#13#10;

/// <summary>Wendet AEdits an; sie dürfen sich nicht überlappen.</summary>
function ApplyEdits(const AText: string; const AEdits: TArray<TTextEdit>): string;
var
  Lines: TArray<string>;
  Order: TArray<Integer>;
  Index, Inner, Swap, Start, Stop: Integer;

  function OffsetOf(const APos: TTextPosition): Integer;
  var
    Line: Integer;
  begin
    Result := 0;
    for Line := 0 to APos.Line - 1 do
      Inc(Result, Length(Lines[Line]) + 1);
    Inc(Result, APos.Character);
  end;

  function Before(A, B: Integer): Boolean;
  begin
    Result := OffsetOf(AEdits[A].Range.StartPos) < OffsetOf(AEdits[B].Range.StartPos);
  end;

begin
  Lines := AText.Split([#10]);
  // Von hinten anwenden; gleiche Stelle in der gegebenen Reihenfolge.
  SetLength(Order, Length(AEdits));
  for Index := 0 to High(Order) do
    Order[Index] := Index;
  for Index := 0 to High(Order) do
    for Inner := Index + 1 to High(Order) do
      if Before(Order[Index], Order[Inner]) or
        ((OffsetOf(AEdits[Order[Index]].Range.StartPos) = OffsetOf(AEdits[Order[Inner]].Range.StartPos)) and
        (Order[Index] < Order[Inner])) then
      begin
        Swap := Order[Index];
        Order[Index] := Order[Inner];
        Order[Inner] := Swap;
      end;
  Result := AText;
  for Index in Order do
  begin
    Start := OffsetOf(AEdits[Index].Range.StartPos);
    Stop := OffsetOf(AEdits[Index].Range.EndPos);
    Result := Copy(Result, 1, Start) + AEdits[Index].NewText + Copy(Result, Stop + 1, MaxInt);
  end;
end;

function SyntaxErrors(const AText: string): Integer;
var
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(AText);
  try
    Result := Length(Tree.Diagnostics);
  finally
    Tree.Free;
  end;
end;

/// <summary>Datei unter Tests/ ab dem Programmordner bzw. dem aktuellen Ordner aufwärts; '' ohne.</summary>
function TestsFile(const ARelative: string): string;
var
  Starts: TArray<string>;
  Start, Directory: string;
begin
  Starts := [ExtractFileDir(ParamStr(0)), GetCurrentDir];
  for Start in Starts do
  begin
    Directory := Start;
    while Directory <> '' do
    begin
      Result := TPath.Combine(Directory, TPath.Combine('Tests', ARelative));
      if TFile.Exists(Result) then
        Exit;
      if ExtractFileDir(Directory) = Directory then
        Break;
      Directory := ExtractFileDir(Directory);
    end;
  end;
  Result := '';
end;

function Golden(const AName: string): string;
var
  FileName: string;
begin
  FileName := TestsFile(TPath.Combine('Common', TPath.Combine('Editing', AName + '.pas')));
  Assert.IsTrue(FileName <> '', 'Golden-Datei nicht gefunden: ' + AName);
  Result := TFile.ReadAllText(FileName, TEncoding.UTF8);
  if (Result <> '') and (Result[1] = #$FEFF) then
    Delete(Result, 1, 1);
end;

/// <summary>Titel aller Aktionen für ALine.</summary>
function Titles(const AText: string; ALine: Integer): string;
var
  Tree: TSyntaxTree;
  Action: TCodeAction;
begin
  Result := '';
  Tree := TPascalParser.Parse(AText);
  try
    for Action in TClassActions.Actions(AText, Tree, ALine, TClassActionContext.Default) do
      Result := Result + Action.Title + '|';
  finally
    Tree.Free;
  end;
end;

{ TClassActionsTests }

procedure TClassActionsTests.PropertyMatchesGoldenFile;
var
  Action: TCodeAction;
  Text: string;
begin
  Assert.IsTrue(TClassActions.PropertyAccessors(PropertyBefore, 14, TClassActionContext.Default, Action));
  Assert.AreEqual('Getter, Setter und Feld für Name erzeugen', Action.Title);
  Text := ApplyEdits(PropertyBefore, Action.Edits);
  Assert.AreEqual(Golden('Atlas.Common.Editing.ClassActions.PropertyGolden'), Text);
  Assert.AreEqual(0, SyntaxErrors(Text));
end;

procedure TClassActionsTests.InterfaceMatchesGoldenFile;
var
  Action: TCodeAction;
  Text: string;
begin
  Assert.IsTrue(TClassActions.ImplementInterface(InterfaceBefore, 16, 'IGoldenZaehler', TClassActionContext.Default,
    Action));
  Assert.AreEqual('Methoden von IGoldenZaehler implementieren', Action.Title);
  Text := ApplyEdits(InterfaceBefore, Action.Edits);
  Assert.AreEqual(Golden('Atlas.Common.Editing.ClassActions.InterfaceGolden'), Text);
  Assert.AreEqual(0, SyntaxErrors(Text));
  // Danach ist nichts mehr zu implementieren.
  Assert.IsFalse(TClassActions.ImplementInterface(Text, 16, 'IGoldenZaehler', TClassActionContext.Default, Action));
end;

procedure TClassActionsTests.OverrideMatchesGoldenFile;
var
  Action: TCodeAction;
  Text: string;
begin
  Assert.AreEqual('Zeichne,Beschreibung', string.Join(',',
    TClassActions.OverrideCandidates(OverrideBefore, 16, TClassActionContext.Default)));
  Assert.IsTrue(TClassActions.OverrideMethod(OverrideBefore, 16, 'Zeichne', TClassActionContext.Default, Action));
  Assert.AreEqual('Zeichne überschreiben', Action.Title);
  Text := ApplyEdits(OverrideBefore, Action.Edits);
  Assert.IsTrue(TClassActions.OverrideMethod(Text, 16, 'Beschreibung', TClassActionContext.Default, Action));
  Text := ApplyEdits(Text, Action.Edits);
  Assert.AreEqual(Golden('Atlas.Common.Editing.ClassActions.OverrideGolden'), Text);
  Assert.AreEqual(0, SyntaxErrors(Text));
  Assert.AreEqual('', string.Join(',', TClassActions.OverrideCandidates(Text, 16, TClassActionContext.Default)));
end;

procedure TClassActionsTests.NoActionsWhereNothingIsMissing;
var
  Action: TCodeAction;
  Text: string;
begin
  // Außerhalb einer Klasse: nichts.
  Assert.AreEqual('', Titles(OverrideBefore, 22));
  Assert.AreEqual('', Titles(InterfaceBefore, 11));
  // Property mit read/write: kein Getter/Setter.
  Text := StringReplace(PropertyBefore, 'property Name: string;', 'property Name: string read FName;',
    [rfReplaceAll]);
  Assert.IsFalse(TClassActions.PropertyAccessors(Text, 14, TClassActionContext.Default, Action));
  Assert.AreEqual(0, Pos('Getter', Titles(Text, 14)));
  // Klasse ohne Vorfahren mit virtuellen Methoden und ohne Interface.
  Assert.AreEqual('', Titles(OverrideBefore, 11));
end;

procedure TClassActionsTests.PropertyKeepsExistingMembers;
var
  Action: TCodeAction;
  Text: string;
begin
  // Feld und Getter gibt es schon: nur der Setter kommt dazu.
  Text := StringReplace(PropertyBefore, '  public'#13#10'    constructor Create;',
    '  private'#13#10'    FName: string;'#13#10'    function GetName: string;'#13#10'  public'#13#10 +
    '    constructor Create;', []);
  Assert.IsTrue(TClassActions.PropertyAccessors(Text, 17, TClassActionContext.Default, Action));
  Text := ApplyEdits(Text, Action.Edits);
  Assert.AreEqual(1, Integer(Length(Text.Split(['FName: string;'])) - 1), Text);
  Assert.AreEqual(1, Integer(Length(Text.Split(['function GetName: string;'])) - 1), Text);
  Assert.IsTrue(Pos('    procedure SetName(const Value: string);', Text) > 0, Text);
  Assert.IsTrue(Pos('property Name: string read GetName write SetName;', Text) > 0, Text);
end;

procedure TClassActionsTests.OverrideOffersOnlyMissingMethods;
var
  Titled: string;
begin
  Titled := Titles(OverrideBefore, 16);
  Assert.IsTrue(Pos('Zeichne überschreiben|', Titled) > 0, Titled);
  Assert.IsTrue(Pos('Beschreibung überschreiben|', Titled) > 0, Titled);
  Titled := Titles(StringReplace(OverrideBefore, '  TGoldenFigur = class(TGoldenBasis)'#13#10,
    '  TGoldenFigur = class(TGoldenBasis)'#13#10'    procedure Zeichne; override;'#13#10, []), 16);
  Assert.AreEqual(0, Pos('Zeichne überschreiben', Titled), Titled);
  Assert.IsTrue(Pos('Beschreibung überschreiben|', Titled) > 0, Titled);
end;

procedure TClassActionsTests.FollowsFormatStyle;
var
  Context: TClassActionContext;
  Action: TCodeAction;
  Text: string;
begin
  Context := TClassActionContext.Default;
  Context.Style.IndentSize := 4;
  Assert.IsTrue(TClassActions.PropertyAccessors(PropertyBefore, 14, Context, Action));
  Text := ApplyEdits(PropertyBefore, Action.Edits);
  Assert.IsTrue(Pos('function TGoldenKunde.GetName: string;'#13#10'begin'#13#10'    Result := FName;', Text) > 0,
    Text);
end;

initialization
  TDUnitX.RegisterTestFixture(TClassActionsTests);

end.
