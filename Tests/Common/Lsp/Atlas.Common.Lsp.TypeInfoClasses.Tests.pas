unit Atlas.Common.Lsp.TypeInfoClasses.Tests;

// Standardsichtbarkeit published (#537): Schalter {$M+}/{$TYPEINFO} an einer
// Stelle (auch in Listen, ohne inaktive Zweige, nicht die Stapelgröße),
// Vorfahrenkette über den Index bis zu einer {$M+}-Klasse, bekannte Klassen
// ohne Index und die Gliederung mit und ohne Index.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Index.Contract;

type
  [TestFixture]
  TTypeInfoClassesTests = class
  private
    FIndex: ISymbolIndex;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ReadsSwitchDirectives;
    [Test]
    procedure SwitchFollowsPositionAndConditionals;
    /// <summary>#847: {$PUSHOPT}/{$POPOPT} sichern und stellen {$M+} wieder her.</summary>
    [Test]
    procedure SwitchFollowsPushAndPopOpt;
    [Test]
    procedure FollowsAncestorsThroughIndex;
    [Test]
    procedure KnownClassesWithoutIndex;
    [Test]
    procedure OutlineUsesTypeInfoForDefaultVisibility;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Lsp.DocumentSymbols,
  Atlas.Common.Lsp.TypeInfoClasses;

const
  BaseFile = 'C:\P\Basis.pas';
  BaseCode =
    'unit Basis;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TSchlicht = class'#10 +
    '  end;'#10 +
    '{$M+}'#10 +
    '  TMitRtti = class'#10 +
    '  end;'#10 +
    '{$M-}'#10 +
    '  TErbe = class(TMitRtti)'#10 +
    '  end;'#10 +
    '  TEnkel = class(TErbe)'#10 +
    '  end;'#10 +
    '  TOhne = class(TSchlicht)'#10 +
    '  end;'#10 +
    '  TZyklusA = class(TZyklusB)'#10 +
    '  end;'#10 +
    '  TZyklusB = class(TZyklusA)'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'end.';

function ReadSource(const AFileName: string; out AText: string): Boolean;
begin
  Result := SameText(AFileName, BaseFile);
  if Result then
    AText := BaseCode;
end;

procedure TTypeInfoClassesTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(BaseCode, BaseFile, nil));
end;

procedure TTypeInfoClassesTests.TearDown;
begin
  FIndex := nil;
end;

procedure TTypeInfoClassesTests.ReadsSwitchDirectives;
var
  Value: Boolean;
begin
  Assert.IsTrue(TTypeInfoClasses.ReadSwitch('{$M+}', Value) and Value);
  Assert.IsTrue(TTypeInfoClasses.ReadSwitch('{$M-}', Value) and not Value);
  Assert.IsTrue(TTypeInfoClasses.ReadSwitch('{$TYPEINFO ON}', Value) and Value);
  Assert.IsTrue(TTypeInfoClasses.ReadSwitch('{$typeinfo off}', Value) and not Value);
  Assert.IsTrue(TTypeInfoClasses.ReadSwitch('{$R-,M+,H+}', Value) and Value);
  Assert.IsTrue(TTypeInfoClasses.ReadSwitch('(*$M+*)', Value) and Value);
  // Stapelgröße und andere Schalter setzen nichts.
  Assert.IsFalse(TTypeInfoClasses.ReadSwitch('{$M 16384,1048576}', Value));
  Assert.IsFalse(TTypeInfoClasses.ReadSwitch('{$R+}', Value));
  Assert.IsFalse(TTypeInfoClasses.ReadSwitch('{ M+ }', Value));
end;

procedure TTypeInfoClassesTests.SwitchFollowsPositionAndConditionals;
const
  Code =
    'unit U;'#10 +
    '{$M+}'#10 +
    'type TA = class end;'#10 +
    '{$M-}'#10 +
    'type TB = class end;'#10 +
    '{$IFDEF GIBTSNICHT}{$M+}{$ENDIF}'#10 +
    'type TC = class end;'#10 +
    '{$IFDEF MSWINDOWS}{$TYPEINFO ON}{$ENDIF}'#10 +
    'type TD = class end;'#10 +
    'end.';
begin
  Assert.IsFalse(TTypeInfoClasses.SwitchAt(Code, TTextPosition.Create(0, 0)));
  Assert.IsTrue(TTypeInfoClasses.SwitchAt(Code, TTextPosition.Create(2, 5)));
  Assert.IsFalse(TTypeInfoClasses.SwitchAt(Code, TTextPosition.Create(4, 5)));
  Assert.IsFalse(TTypeInfoClasses.SwitchAt(Code, TTextPosition.Create(6, 5)), 'inaktiver Zweig');
  Assert.IsTrue(TTypeInfoClasses.SwitchAt(Code, TTextPosition.Create(8, 5)), 'aktiver Zweig');
end;

procedure TTypeInfoClassesTests.SwitchFollowsPushAndPopOpt;
const
  Code =
    'unit U;'#10 +           // 0
    '{$M+}'#10 +             // 1
    '{$PUSHOPT}'#10 +        // 2
    '{$M-}'#10 +             // 3
    'type TA = class end;'#10 + // 4
    '{$POPOPT}'#10 +         // 5
    'type TB = class end;'#10 + // 6
    '{$POPOPT}'#10 +         // 7
    'type TC = class end;'#10 + // 8
    'end.';
begin
  Assert.IsFalse(TTypeInfoClasses.SwitchAt(Code, TTextPosition.Create(4, 5)));
  Assert.IsTrue(TTypeInfoClasses.SwitchAt(Code, TTextPosition.Create(6, 5)));
  // {$POPOPT} ohne {$PUSHOPT} ändert nichts.
  Assert.IsTrue(TTypeInfoClasses.SwitchAt(Code, TTextPosition.Create(8, 5)));
end;

procedure TTypeInfoClassesTests.FollowsAncestorsThroughIndex;
var
  Classes: TTypeInfoClasses;
begin
  Classes := TTypeInfoClasses.Create(FIndex, ReadSource);
  try
    Assert.IsFalse(Classes.HasTypeInfo('TSchlicht'));
    Assert.IsTrue(Classes.HasTypeInfo('TMitRtti'), '{$M+} bei der Deklaration');
    Assert.IsTrue(Classes.HasTypeInfo('TErbe'), 'Vorfahr mit {$M+}');
    Assert.IsTrue(Classes.HasTypeInfo('Basis.TEnkel'), 'über zwei Stufen, qualifiziert');
    Assert.IsFalse(Classes.HasTypeInfo('TOhne'));
    Assert.IsFalse(Classes.HasTypeInfo('TZyklusA'), 'Zyklus bricht ab');
    Assert.IsFalse(Classes.HasTypeInfo('TObject'));
    Assert.IsFalse(Classes.HasTypeInfo('TUnbekannt'));
    // Nicht im Index, aber bekannt.
    Assert.IsTrue(Classes.HasTypeInfo('Vcl.Forms.TForm'));
  finally
    Classes.Free;
  end;
end;

procedure TTypeInfoClassesTests.KnownClassesWithoutIndex;
var
  Classes: TTypeInfoClasses;
begin
  Assert.IsTrue(TTypeInfoClasses.KnownTypeInfoClass('TPersistent'));
  Assert.IsTrue(TTypeInfoClasses.KnownTypeInfoClass('TFrame'));
  Assert.IsTrue(TTypeInfoClasses.KnownTypeInfoClass('System.Classes.TComponent'));
  Assert.IsFalse(TTypeInfoClasses.KnownTypeInfoClass('TInterfacedObject'));
  Assert.IsFalse(TTypeInfoClasses.KnownTypeInfoClass('Exception'));
  Assert.IsFalse(TTypeInfoClasses.KnownTypeInfoClass('TList'));
  Classes := TTypeInfoClasses.Create(nil, nil);
  try
    Assert.IsTrue(Classes.HasTypeInfo('TDataModule'));
    Assert.IsFalse(Classes.HasTypeInfo('TMitRtti'), 'ohne Index unbekannt');
  finally
    Classes.Free;
  end;
end;

function VisibilityOf(const ASymbols: TJSONArray; const AName: string): string;
var
  Item: TJSONValue;
  Entry: TJSONObject;
  Children: TJSONValue;
begin
  Result := '';
  for Item in ASymbols do
  begin
    Entry := Item as TJSONObject;
    if (Entry.GetValue<string>('name', '') = AName) and (Entry.GetValue('atlas') is TJSONObject) then
      Exit(TJSONObject(Entry.GetValue('atlas')).GetValue<string>('visibility', ''));
    Children := Entry.GetValue('children');
    if Children is TJSONArray then
    begin
      Result := VisibilityOf(TJSONArray(Children), AName);
      if Result <> '' then
        Exit;
    end;
  end;
end;

procedure TTypeInfoClassesTests.OutlineUsesTypeInfoForDefaultVisibility;
const
  Code =
    'unit U;'#10 +
    'interface'#10 +
    'uses Basis;'#10 +
    'type'#10 +
    '  TEigene = class(TErbe)'#10 +
    '    A: Integer;'#10 +
    '  end;'#10 +
    '  TFremd = class(TOhne)'#10 +
    '    B: Integer;'#10 +
    '  end;'#10 +
    '{$M+}'#10 +
    '  TLokal = class'#10 +
    '    C: Integer;'#10 +
    '  end;'#10 +
    '{$M-}'#10 +
    '  TVomLokalen = class(TLokal)'#10 +
    '    D: Integer;'#10 +
    '  end;'#10 +
    '  TFormular = class(TForm)'#10 +
    '    E: Integer;'#10 +
    '  end;'#10 +
    '  TListe = class(TInterfacedObject, IInterface)'#10 +
    '    F: Integer;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'end.';
var
  Tree: TSyntaxTree;
  Symbols: TJSONArray;
begin
  Tree := TPascalParser.Parse(Code);
  try
    Symbols := TLspDocumentSymbols.BuildSymbols(Tree, Code, FIndex, ReadSource);
    try
      Assert.AreEqual('published', VisibilityOf(Symbols, 'A'), 'Vorfahr im Index mit {$M+}');
      Assert.AreEqual('public', VisibilityOf(Symbols, 'B'), 'Vorfahr im Index ohne');
      Assert.AreEqual('published', VisibilityOf(Symbols, 'C'), '{$M+} in der Datei');
      Assert.AreEqual('published', VisibilityOf(Symbols, 'D'), 'Vorfahr in derselben Datei');
      Assert.AreEqual('published', VisibilityOf(Symbols, 'E'), 'bekannte VCL-Klasse');
      Assert.AreEqual('public', VisibilityOf(Symbols, 'F'));
    finally
      Symbols.Free;
    end;
    // Ohne Index: nur Datei und bekannte Klassen.
    Symbols := TLspDocumentSymbols.BuildSymbols(Tree, Code);
    try
      Assert.AreEqual('public', VisibilityOf(Symbols, 'A'));
      Assert.AreEqual('published', VisibilityOf(Symbols, 'D'));
      Assert.AreEqual('published', VisibilityOf(Symbols, 'E'));
    finally
      Symbols.Free;
    end;
  finally
    Tree.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTypeInfoClassesTests);

end.
