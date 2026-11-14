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
  System.Generics.Collections,
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
  cPanelsFile = 'C:\P\Panels.pas';
  cMainFile = 'C:\P\Main.pas';
  cMainForm = 'C:\P\Main.dfm';

  cUnitPanels =
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
  cUnitMain =
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
  cFormMain =
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
  if SameText(AFileName, cPanelsFile) then
  begin
    Result := cUnitPanels;
  end
  else if SameText(AFileName, cMainFile) then
  begin
    Result := cUnitMain;
  end
  else if SameText(AFileName, cMainForm) then
  begin
    Result := cFormMain;
  end
  else
  begin
    Result := '';
  end;
end;

function Apply(const AText: string; ADocument: TJSONObject): string;
var
  mItem: TJSONValue;
  mEdits: TArray<TTextEdit>;
  mRange: TJSONObject;
begin
  mEdits := nil;
  for mItem in ADocument.GetValue('edits') as TJSONArray do
  begin
    mRange := TJSONObject(mItem).GetValue('range') as TJSONObject;
    mEdits := mEdits + [TTextEdit.Create(TTextRange.Create(TLspPositions.ReadPosition(mRange.GetValue('start')),
      TLspPositions.ReadPosition(mRange.GetValue('end'))), TJSONObject(mItem).GetValue('newText').Value)];
  end;
  Result := TChangeSignature.ApplyEdits(AText, mEdits);
end;

function Context(const AIndex: ISymbolIndex): TInvertBooleanContext;
begin
  Result := Default(TInvertBooleanContext);
  Result.Index := AIndex;
  Result.Files := [cPanelsFile, cMainFile];
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
  mTree: TSyntaxTree;
  mResolver: TNameResolver;
  mAnswer: TJSONObject;
  mItem: TJSONValue;
  mDocument: TJSONObject;
  mFileName: string;
  mContext: TInvertBooleanContext;
begin
  Result := nil;
  AWarnings := nil;
  mTree := TPascalParser.Parse(TextOf(AFileName));
  mResolver := TNameResolver.Create(AIndex, nil);
  mAnswer := nil;
  try
    mContext := Context(AIndex);
    mContext.NewName := ANewName;
    mAnswer := TLspInvertBoolean.Execute(mResolver, mTree, AFileName, TextOf(AFileName), APosition, mContext);
    for mItem in (mAnswer.GetValue('edit') as TJSONObject).GetValue('documentChanges') as TJSONArray do
    begin
      mDocument := TJSONObject(mItem);
      mFileName := TDocumentUris.ToPath((mDocument.GetValue('textDocument') as TJSONObject).GetValue('uri').Value);
      Result := Result + [ExtractFileName(mFileName) + '|' + Apply(TextOf(mFileName), mDocument)];
    end;
    for mItem in mAnswer.GetValue('warnings') as TJSONArray do
    begin
      AWarnings := AWarnings + [mItem.Value];
    end;
  finally
    mAnswer.Free;
    mResolver.Free;
    mTree.Free;
  end;
end;

function FileText(const AResults: TArray<string>; const AName: string): string;
var
  mItem: string;
begin
  for mItem in AResults do
  begin
    if SameText(Copy(mItem, 1, Pos('|', mItem) - 1), AName) then
    begin
      Exit(Copy(mItem, Pos('|', mItem) + 1, MaxInt));
    end;
  end;
  Result := '';
end;

procedure TLspInvertBooleanTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitPanels, cPanelsFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitMain, cMainFile, nil));
end;

procedure TLspInvertBooleanTests.TearDown;
begin
  FIndex := nil;
end;

procedure TLspInvertBooleanTests.PropertyWithFieldSetterAndForm;
var
  mResults, mWarnings: TArray<string>;
  mPanels, mMain, mForm: string;
begin
  mResults := Run(FIndex, cPanelsFile, TTextPosition.Create(12, 14), 'Visible', mWarnings);
  mPanels := FileText(mResults, 'Panels.pas');
  mMain := FileText(mResults, 'Main.pas');
  mForm := FileText(mResults, 'Main.dfm');
  Assert.AreEqual(3, Integer(Length(mResults)), string.Join(#10'----'#10, mResults));
  Assert.Contains(mPanels, '    FVisible: Boolean;'#10'    procedure SetVisible(const Value: Boolean);');
  Assert.Contains(mPanels, '    property Visible: Boolean read FVisible write SetVisible default True;');
  // Das Feld startet mit False; umgekehrt setzt der Konstruktor True.
  Assert.Contains(mPanels, '  inherited Create;'#10'  FVisible := True;'#10'  Ready := True;');
  Assert.Contains(mPanels, 'procedure TFooPanel.SetVisible(const Value: Boolean);'#10'begin'#10 +
    '  if FVisible = Value then'#10'    Exit;'#10'  FVisible := Value;');
  Assert.Contains(mPanels, '    SetVisible(True);');
  Assert.Contains(mMain, '  P.Visible := P.IsEmpty;'#10'  if not P.Visible then');
  Assert.Contains(mForm, '  object Panel1: TFooPanel'#10'    Visible = False');
  Assert.Contains(mForm, '  object Panel2: TBigPanel'#10'    Visible = True');
  Assert.Contains(mForm, '  object Other1: TOther'#10'    Hidden = True');
  Assert.IsTrue(Length(mWarnings) >= 2, string.Join(#10, mWarnings));
  Assert.Contains(string.Join(#10, mWarnings), 'Main.pas, Zeile 14');
  Assert.Contains(string.Join(#10, mWarnings), 'published');
end;

procedure TLspInvertBooleanTests.FunctionWithOverride;
var
  mResults, mWarnings: TArray<string>;
  mPanels, mMain: string;
begin
  mResults := Run(FIndex, cPanelsFile, TTextPosition.Create(9, 14), 'HasItems', mWarnings);
  mPanels := FileText(mResults, 'Panels.pas');
  mMain := FileText(mResults, 'Main.pas');
  Assert.Contains(mPanels, '    function HasItems: Boolean; virtual;');
  Assert.Contains(mPanels, '    function HasItems: Boolean; override;');
  Assert.Contains(mPanels, 'function TFooPanel.HasItems: Boolean;'#10'begin'#10'  Result := False;');
  Assert.Contains(mPanels, 'function TBigPanel.HasItems: Boolean;'#10'begin'#10 +
    '  Result := inherited HasItems or Ready;');
  Assert.Contains(mMain, '  P.Hidden := P.HasItems;');
end;

procedure TLspInvertBooleanTests.ParameterWithDefault;
var
  mResults, mWarnings: TArray<string>;
  mPanels, mMain: string;
begin
  mResults := Run(FIndex, cPanelsFile, TTextPosition.Create(10, 20), 'ASlow', mWarnings);
  mPanels := FileText(mResults, 'Panels.pas');
  mMain := FileText(mResults, 'Main.pas');
  Assert.Contains(mPanels, '    procedure Show(ASlow: Boolean = True);');
  Assert.Contains(mPanels, 'procedure TFooPanel.Show(ASlow: Boolean);'#10'begin'#10'  if ASlow then');
  Assert.Contains(mMain, '    P.Show(False);'#10'  P.Show;');
end;

procedure TLspInvertBooleanTests.GlobalVariableGetsStartValue;
var
  mResults, mWarnings: TArray<string>;
  mPanels, mMain: string;
begin
  mResults := Run(FIndex, cPanelsFile, TTextPosition.Create(19, 3), 'NotReady', mWarnings);
  mPanels := FileText(mResults, 'Panels.pas');
  mMain := FileText(mResults, 'Main.pas');
  Assert.Contains(mPanels, '  NotReady: Boolean = True;');
  Assert.Contains(mPanels, '  NotReady := False;');
  Assert.Contains(mPanels, '  Result := inherited IsEmpty and NotReady;');
  Assert.Contains(mMain, '  if not NotReady then');
end;

procedure TLspInvertBooleanTests.AccessorFieldIsRefused;
var
  mWarnings: TArray<string>;
begin
  Assert.WillRaise(
    procedure
    begin
      Run(FIndex, cPanelsFile, TTextPosition.Create(5, 5), 'FVisible', mWarnings);
    end, EJsonRpcError);
  // Prozeduren sind keine Booleans.
  Assert.WillRaise(
    procedure
    begin
      Run(FIndex, cPanelsFile, TTextPosition.Create(10, 15), 'Hide', mWarnings);
    end, EJsonRpcError);
end;

procedure TLspInvertBooleanTests.ActionFollowsSetting;
var
  mTree: TSyntaxTree;
  mResolver: TNameResolver;
  mActions: TArray<TJSONObject>;
  mAction: TJSONObject;
begin
  mTree := TPascalParser.Parse(cUnitPanels);
  mResolver := TNameResolver.Create(FIndex, nil);
  try
    mActions := TLspInvertBoolean.Actions(mResolver, mTree, cPanelsFile, 'file:///C:/P/Panels.pas',
      TTextPosition.Create(5, 5), Context(FIndex));
    try
      Assert.AreEqual(1, Integer(Length(mActions)));
      Assert.AreEqual('Bedeutung umkehren (FHidden → FVisible)', mActions[0].GetValue('title').Value);
      Assert.AreEqual(TLspInvertBoolean.cClientCommand,
        (mActions[0].GetValue('command') as TJSONObject).GetValue('command').Value);
    finally
      for mAction in mActions do
      begin
        mAction.Free;
      end;
    end;
    Assert.AreEqual(0, Integer(Length(TLspInvertBoolean.Actions(mResolver, mTree, cPanelsFile,
      'file:///C:/P/Panels.pas', TTextPosition.Create(10, 15), Context(FIndex)))));
  finally
    mResolver.Free;
    mTree.Free;
  end;
end;

procedure TLspInvertBooleanTests.ReadsParameterModifiers;
const
  cSignature = 'procedure Toggle(var A, B: Boolean; C: Integer; out D: Boolean; [ref] const E: Boolean)';
begin
  Assert.AreEqual('var', TLspInvertBoolean.ParameterModifier(cSignature, 0));
  Assert.AreEqual('var', TLspInvertBoolean.ParameterModifier(cSignature, 1));
  Assert.AreEqual('', TLspInvertBoolean.ParameterModifier(cSignature, 2));
  Assert.AreEqual('out', TLspInvertBoolean.ParameterModifier(cSignature, 3));
  Assert.AreEqual('', TLspInvertBoolean.ParameterModifier(cSignature, 4));
  Assert.AreEqual('', TLspInvertBoolean.ParameterModifier('procedure Run', 0));
end;

initialization
  TDUnitX.RegisterTestFixture(TLspInvertBooleanTests);

end.
