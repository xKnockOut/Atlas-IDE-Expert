unit Atlas.Common.Lsp.InvertBoolean.Tests;

// Tests für „Boolean umkehren“ über das Protokoll (#715): Property samt Feld,
// Setter, default und Formular, Funktion mit Überschreibung, Parameter mit
// Standardwert, globale Variable mit Startwert, Abbruch bei Zugriffsfeldern
// und die Code-Aktion.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Index.Contract;

type
  [TestFixture]
  TLspInvertBooleanTests = class
  private
    FIndex: ISymbolIndex;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure PropertyWithFieldSetterAndForm;
    [Test]
    procedure FunctionWithOverride;
    [Test]
    procedure ParameterWithDefault;
    [Test]
    procedure GlobalVariableGetsStartValue;
    [Test]
    procedure AccessorFieldIsRefused;
    [Test]
    procedure ActionFollowsSetting;
    [Test]
    procedure ReadsParameterModifiers;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Lsp.InvertBoolean;

const
  PanelsFile = 'C:\P\Panels.pas';
  MainFile = 'C:\P\Main.pas';
  MainForm = 'C:\P\Main.dfm';

  UnitPanels =
    'unit Panels;'#10 +                                                                // 0
    'interface'#10 +                                                                   // 1
    'type'#10 +                                                                        // 2
    '  TFooPanel = class(TObject)'#10 +                                                // 3
    '  private'#10 +                                                                   // 4
    '    FHidden: Boolean;'#10 +                                                       // 5
    '    procedure SetHidden(const Value: Boolean);'#10 +                              // 6
    '  public'#10 +                                                                    // 7
    '    constructor Create;'#10 +                                                     // 8
    '    function IsEmpty: Boolean; virtual;'#10 +                                     // 9
    '    procedure Show(AQuick: Boolean = False);'#10 +                                // 10
    '  published'#10 +                                                                 // 11
    '    property Hidden: Boolean read FHidden write SetHidden default False;'#10 +    // 12
    '  end;'#10 +                                                                      // 13
    '  TBigPanel = class(TFooPanel)'#10 +                                              // 14
    '  public'#10 +                                                                    // 15
    '    function IsEmpty: Boolean; override;'#10 +                                    // 16
    '  end;'#10 +                                                                      // 17
    'var'#10 +                                                                         // 18
    '  Ready: Boolean;'#10 +                                                           // 19
    'implementation'#10 +                                                              // 20
    'constructor TFooPanel.Create;'#10 +
    'begin'#10 +
    '  inherited Create;'#10 +
    '  Ready := True;'#10 +
    'end;'#10 +
    'procedure TFooPanel.SetHidden(const Value: Boolean);'#10 +
    'begin'#10 +
    '  if FHidden = Value then'#10 +
    '    Exit;'#10 +
    '  FHidden := Value;'#10 +
    'end;'#10 +
    'function TFooPanel.IsEmpty: Boolean;'#10 +
    'begin'#10 +
    '  Result := True;'#10 +
    'end;'#10 +
    'procedure TFooPanel.Show(AQuick: Boolean);'#10 +
    'begin'#10 +
    '  if not AQuick then'#10 +
    '    SetHidden(False);'#10 +
    'end;'#10 +
    'function TBigPanel.IsEmpty: Boolean;'#10 +
    'begin'#10 +
    '  Result := inherited IsEmpty and not Ready;'#10 +
    'end;'#10 +
    'end.'#10;
  UnitMain =
    'unit Main;'#10 +
    'interface'#10 +
    'uses'#10 +
    '  Panels;'#10 +
    'procedure Run(P: TFooPanel);'#10 +
    'implementation'#10 +
    'procedure Run(P: TFooPanel);'#10 +
    'begin'#10 +
    '  P.Hidden := not P.IsEmpty;'#10 +
    '  if P.Hidden then'#10 +
    '    P.Show(True);'#10 +
    '  P.Show;'#10 +
    '  if Ready then'#10 +
    '    Log(''Hidden'');'#10 +
    'end;'#10 +
    'end.'#10;
  FormMain =
    'object Form1: TForm1'#10 +
    '  object Panel1: TFooPanel'#10 +
    '    Hidden = True'#10 +
    '  end'#10 +
    '  object Panel2: TBigPanel'#10 +
    '    Hidden = False'#10 +
    '  end'#10 +
    '  object Other1: TOther'#10 +
    '    Hidden = True'#10 +
    '  end'#10 +
    'end'#10;

function TextOf(const AFileName: string): string;
begin
  if SameText(AFileName, PanelsFile) then
    Result := UnitPanels
  else if SameText(AFileName, MainFile) then
    Result := UnitMain
  else if SameText(AFileName, MainForm) then
    Result := FormMain
  else
    Result := '';
end;

function Apply(const AText: string; ADocument: TJSONObject): string;
var
  Item: TJSONValue;
  Edits: TArray<TTextEdit>;
  Range: TJSONObject;
begin
  Edits := nil;
  for Item in ADocument.GetValue('edits') as TJSONArray do
  begin
    Range := TJSONObject(Item).GetValue('range') as TJSONObject;
    Edits := Edits + [TTextEdit.Create(TTextRange.Create(TLspPositions.ReadPosition(Range.GetValue('start')),
      TLspPositions.ReadPosition(Range.GetValue('end'))), TJSONObject(Item).GetValue('newText').Value)];
  end;
  Result := TChangeSignature.ApplyEdits(AText, Edits);
end;

function Context(const AIndex: ISymbolIndex): TInvertBooleanContext;
begin
  Result := Default(TInvertBooleanContext);
  Result.Index := AIndex;
  Result.Files := [PanelsFile, MainFile];
  Result.Prefix := 'Not';
  Result.IncludeDfm := True;
  Result.ReadText :=
    function(const AFileName: string; out AText: string): Boolean
    begin
      AText := TextOf(AFileName);
      Result := AText <> '';
    end;
end;

/// <summary>Neuer Text je Datei, Name → Text; AWarnings: Hinweise.</summary>
function Run(const AIndex: ISymbolIndex; const AFileName: string; const APosition: TTextPosition;
  const ANewName: string; out AWarnings: TArray<string>): TArray<string>;
var
  Tree: TSyntaxTree;
  Resolver: TNameResolver;
  Answer: TJSONObject;
  Item: TJSONValue;
  Document: TJSONObject;
  FileName: string;
begin
  Result := nil;
  AWarnings := nil;
  Tree := TPascalParser.Parse(TextOf(AFileName));
  Resolver := TNameResolver.Create(AIndex, nil);
  Answer := nil;
  try
    Answer := TLspInvertBoolean.Execute(Resolver, Tree, AFileName, TextOf(AFileName), APosition, ANewName,
      Context(AIndex));
    for Item in (Answer.GetValue('edit') as TJSONObject).GetValue('documentChanges') as TJSONArray do
    begin
      Document := TJSONObject(Item);
      FileName := TDocumentUris.ToPath((Document.GetValue('textDocument') as TJSONObject).GetValue('uri').Value);
      Result := Result + [ExtractFileName(FileName) + '|' + Apply(TextOf(FileName), Document)];
    end;
    for Item in Answer.GetValue('warnings') as TJSONArray do
      AWarnings := AWarnings + [Item.Value];
  finally
    Answer.Free;
    Resolver.Free;
    Tree.Free;
  end;
end;

function FileText(const AResults: TArray<string>; const AName: string): string;
var
  Item: string;
begin
  for Item in AResults do
    if SameText(Copy(Item, 1, Pos('|', Item) - 1), AName) then
      Exit(Copy(Item, Pos('|', Item) + 1, MaxInt));
  Result := '';
end;

procedure TLspInvertBooleanTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitPanels, PanelsFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitMain, MainFile, nil));
end;

procedure TLspInvertBooleanTests.TearDown;
begin
  FIndex := nil;
end;

procedure TLspInvertBooleanTests.PropertyWithFieldSetterAndForm;
var
  Results, Warnings: TArray<string>;
  Panels, Main, Form: string;
begin
  Results := Run(FIndex, PanelsFile, TTextPosition.Create(12, 14), 'Visible', Warnings);
  Panels := FileText(Results, 'Panels.pas');
  Main := FileText(Results, 'Main.pas');
  Form := FileText(Results, 'Main.dfm');
  Assert.AreEqual(3, Integer(Length(Results)), string.Join(#10'----'#10, Results));
  Assert.Contains(Panels, '    FVisible: Boolean;'#10'    procedure SetVisible(const Value: Boolean);');
  Assert.Contains(Panels, '    property Visible: Boolean read FVisible write SetVisible default True;');
  // Das Feld startet mit False; umgekehrt setzt der Konstruktor True.
  Assert.Contains(Panels, '  inherited Create;'#10'  FVisible := True;'#10'  Ready := True;');
  Assert.Contains(Panels, 'procedure TFooPanel.SetVisible(const Value: Boolean);'#10'begin'#10 +
    '  if FVisible = Value then'#10'    Exit;'#10'  FVisible := Value;');
  Assert.Contains(Panels, '    SetVisible(True);');
  Assert.Contains(Main, '  P.Visible := P.IsEmpty;'#10'  if not P.Visible then');
  Assert.Contains(Form, '  object Panel1: TFooPanel'#10'    Visible = False');
  Assert.Contains(Form, '  object Panel2: TBigPanel'#10'    Visible = True');
  Assert.Contains(Form, '  object Other1: TOther'#10'    Hidden = True');
  Assert.IsTrue(Length(Warnings) >= 2, string.Join(#10, Warnings));
  Assert.Contains(string.Join(#10, Warnings), 'Main.pas, Zeile 14');
  Assert.Contains(string.Join(#10, Warnings), 'published');
end;

procedure TLspInvertBooleanTests.FunctionWithOverride;
var
  Results, Warnings: TArray<string>;
  Panels, Main: string;
begin
  Results := Run(FIndex, PanelsFile, TTextPosition.Create(9, 14), 'HasItems', Warnings);
  Panels := FileText(Results, 'Panels.pas');
  Main := FileText(Results, 'Main.pas');
  Assert.Contains(Panels, '    function HasItems: Boolean; virtual;');
  Assert.Contains(Panels, '    function HasItems: Boolean; override;');
  Assert.Contains(Panels, 'function TFooPanel.HasItems: Boolean;'#10'begin'#10'  Result := False;');
  Assert.Contains(Panels, 'function TBigPanel.HasItems: Boolean;'#10'begin'#10 +
    '  Result := inherited HasItems or Ready;');
  Assert.Contains(Main, '  P.Hidden := P.HasItems;');
end;

procedure TLspInvertBooleanTests.ParameterWithDefault;
var
  Results, Warnings: TArray<string>;
  Panels, Main: string;
begin
  Results := Run(FIndex, PanelsFile, TTextPosition.Create(10, 20), 'ASlow', Warnings);
  Panels := FileText(Results, 'Panels.pas');
  Main := FileText(Results, 'Main.pas');
  Assert.Contains(Panels, '    procedure Show(ASlow: Boolean = True);');
  Assert.Contains(Panels, 'procedure TFooPanel.Show(ASlow: Boolean);'#10'begin'#10'  if ASlow then');
  Assert.Contains(Main, '    P.Show(False);'#10'  P.Show;');
end;

procedure TLspInvertBooleanTests.GlobalVariableGetsStartValue;
var
  Results, Warnings: TArray<string>;
  Panels, Main: string;
begin
  Results := Run(FIndex, PanelsFile, TTextPosition.Create(19, 3), 'NotReady', Warnings);
  Panels := FileText(Results, 'Panels.pas');
  Main := FileText(Results, 'Main.pas');
  Assert.Contains(Panels, '  NotReady: Boolean = True;');
  Assert.Contains(Panels, '  NotReady := False;');
  Assert.Contains(Panels, '  Result := inherited IsEmpty and NotReady;');
  Assert.Contains(Main, '  if not NotReady then');
end;

procedure TLspInvertBooleanTests.AccessorFieldIsRefused;
var
  Warnings: TArray<string>;
begin
  Assert.WillRaise(
    procedure
    begin
      Run(FIndex, PanelsFile, TTextPosition.Create(5, 5), 'FVisible', Warnings);
    end, EJsonRpcError);
  // Prozeduren sind keine Booleans.
  Assert.WillRaise(
    procedure
    begin
      Run(FIndex, PanelsFile, TTextPosition.Create(10, 15), 'Hide', Warnings);
    end, EJsonRpcError);
end;

procedure TLspInvertBooleanTests.ActionFollowsSetting;
var
  Tree: TSyntaxTree;
  Resolver: TNameResolver;
  Actions: TArray<TJSONObject>;
  Action: TJSONObject;
begin
  Tree := TPascalParser.Parse(UnitPanels);
  Resolver := TNameResolver.Create(FIndex, nil);
  try
    Actions := TLspInvertBoolean.Actions(True, Resolver, Tree, PanelsFile, 'file:///C:/P/Panels.pas',
      TTextPosition.Create(5, 5), Context(FIndex));
    try
      Assert.AreEqual(1, Integer(Length(Actions)));
      Assert.AreEqual('Bedeutung umkehren (FHidden → FVisible)', Actions[0].GetValue('title').Value);
      Assert.AreEqual(TLspInvertBoolean.ClientCommand,
        (Actions[0].GetValue('command') as TJSONObject).GetValue('command').Value);
    finally
      for Action in Actions do
        Action.Free;
    end;
    Assert.AreEqual(0, Integer(Length(TLspInvertBoolean.Actions(False, Resolver, Tree, PanelsFile,
      'file:///C:/P/Panels.pas', TTextPosition.Create(5, 5), Context(FIndex)))));
    Assert.AreEqual(0, Integer(Length(TLspInvertBoolean.Actions(True, Resolver, Tree, PanelsFile,
      'file:///C:/P/Panels.pas', TTextPosition.Create(10, 15), Context(FIndex)))));
  finally
    Resolver.Free;
    Tree.Free;
  end;
end;

procedure TLspInvertBooleanTests.ReadsParameterModifiers;
const
  Signature = 'procedure Toggle(var A, B: Boolean; C: Integer; out D: Boolean; [ref] const E: Boolean)';
begin
  Assert.AreEqual('var', TLspInvertBoolean.ParameterModifier(Signature, 0));
  Assert.AreEqual('var', TLspInvertBoolean.ParameterModifier(Signature, 1));
  Assert.AreEqual('', TLspInvertBoolean.ParameterModifier(Signature, 2));
  Assert.AreEqual('out', TLspInvertBoolean.ParameterModifier(Signature, 3));
  Assert.AreEqual('', TLspInvertBoolean.ParameterModifier(Signature, 4));
  Assert.AreEqual('', TLspInvertBoolean.ParameterModifier('procedure Run', 0));
end;

initialization
  TDUnitX.RegisterTestFixture(TLspInvertBooleanTests);

end.
