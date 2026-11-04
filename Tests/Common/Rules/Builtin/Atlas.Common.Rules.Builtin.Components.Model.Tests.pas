unit Atlas.Common.Rules.Builtin.Components.Model.Tests;

// Tests des Modells der Komponentenregeln (Atlas.Common.Rules.Builtin.Components.Model): Klassen und Methoden der
// Datei, Eigenschaften mit read/write/default, Direktiven, bekannte VCL-Basisklassen, Vorfahr laut Deklaration,
// eigene Felder sowie Parameter und lokale Variablen einer Methode.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TComponentModelTests = class
  public
    [Test]
    procedure ClassesAndMethods;
    [Test]
    procedure PropertiesAndDirectives;
    [Test]
    procedure KnownBases;
    [Test]
    procedure DeclarationHelpers;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Index.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Rules.Builtin.Components.Model;

const
  cSource = 'unit U;'#10'interface'#10'type'#10 +
    '  TFoo = class(TCustomControl)'#10 +
    '    FA, FB: Integer;'#10 +
    '    FColor: TColor;'#10 +
    '    procedure Paint; override;'#10 +
    '    procedure SetColor(AValue: TColor);'#10 +
    '    property Color: TColor read FColor write SetColor default clRed;'#10 +
    '  end;'#10 +
    '  TBar = class'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure TFoo.Paint;'#10'begin'#10'  inherited;'#10'end;'#10 +
    'procedure TFoo.SetColor(AValue: TColor);'#10'var'#10'  mOld, mNew: TColor;'#10'begin'#10 +
    '  FColor := AValue;'#10'end;'#10 +
    'end.';

/// <summary>Modell über cSource ohne Symbolindex; AModel und ATree gibt der Aufrufer frei.</summary>
procedure BuildModel(out ATree: TSyntaxTree; out AModel: TComponentModel);
var
  mContext: TRuleContext;
begin
  ATree := TPascalParser.Parse(cSource);
  mContext := Default(TRuleContext);
  mContext.Text := cSource;
  mContext.Tree := ATree;
  AModel := TComponentModel.Create(mContext, Default(TUnitIndex));
end;

procedure TComponentModelTests.ClassesAndMethods;
var
  mTree: TSyntaxTree;
  mModel: TComponentModel;
  mMethod: TMethodImpl;
begin
  BuildModel(mTree, mModel);
  try
    Assert.AreEqual(2, mModel.Classes.Count);
    Assert.AreEqual('TFoo', mModel.Classes[0].Name);
    Assert.AreEqual(2, mModel.Methods.Count);
    Assert.IsTrue(mModel.FindMethod('TFoo', 'Paint', mMethod));
    Assert.IsTrue(mModel.HasToken(mMethod.Block, ['inherited']));
    Assert.IsFalse(mModel.FindMethod('TBar', 'Paint', mMethod));
    Assert.AreEqual(#10, mModel.LineBreak);
  finally
    mModel.Free;
    mTree.Free;
  end;
end;

procedure TComponentModelTests.PropertiesAndDirectives;
var
  mTree: TSyntaxTree;
  mModel: TComponentModel;
  mProps: TArray<TPropertyInfo>;
begin
  BuildModel(mTree, mModel);
  try
    mProps := mModel.Properties(mModel.Classes[0]);
    Assert.AreEqual(1, Integer(Length(mProps)));
    Assert.AreEqual('FColor', mProps[0].ReadName);
    Assert.AreEqual('SetColor', mProps[0].WriteName);
    Assert.IsTrue(mProps[0].HasDefault);
    Assert.AreEqual('clRed', mProps[0].DefaultText);
    Assert.IsTrue(mModel.DeclaredWith(mModel.Classes[0], 'Paint', 'override'));
    Assert.IsFalse(mModel.DeclaredWith(mModel.Classes[0], 'SetColor', 'override'));
    mProps := nil;
  finally
    mModel.Free;
    mTree.Free;
  end;
end;

procedure TComponentModelTests.KnownBases;
var
  mTree: TSyntaxTree;
  mModel: TComponentModel;
begin
  BuildModel(mTree, mModel);
  try
    Assert.IsTrue(mModel.IsComponent('TCustomControl'));
    Assert.IsFalse(mModel.IsComponent('TObject'));
    Assert.IsTrue(IsIn('tpanel', ComponentBases));
    Assert.IsFalse(IsIn('TStringList', ComponentBases));
  finally
    mModel.Free;
    mTree.Free;
  end;
end;

procedure TComponentModelTests.DeclarationHelpers;
var
  mTree: TSyntaxTree;
  mModel: TComponentModel;
  mMethod: TMethodImpl;
begin
  BuildModel(mTree, mModel);
  try
    Assert.AreEqual('TCustomControl', DeclaredParent(mModel.Classes[0]));
    Assert.AreEqual('', DeclaredParent(mModel.Classes[1]));
    Assert.AreEqual('FA,FB,FColor', string.Join(',', OwnFields(mModel.Classes[0])));
    Assert.IsTrue(mModel.FindMethod('TFoo', 'SetColor', mMethod));
    Assert.AreEqual('AValue,mOld,mNew', string.Join(',', MethodLocalNames(mMethod)));
  finally
    mModel.Free;
    mTree.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TComponentModelTests);

end.
