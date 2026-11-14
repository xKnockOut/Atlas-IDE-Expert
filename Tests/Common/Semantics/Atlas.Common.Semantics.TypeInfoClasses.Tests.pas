unit Atlas.Common.Semantics.TypeInfoClasses.Tests;

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
  Atlas.Common.Semantics.TypeInfoClasses;

const
  cBaseFile = 'C:\P\Basis.pas';
  cBaseCode =
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
  Result := SameText(AFileName, cBaseFile);
  if Result then
  begin
    AText := cBaseCode;
  end;
end;

procedure TTypeInfoClassesTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(cBaseCode, cBaseFile, nil));
end;

procedure TTypeInfoClassesTests.TearDown;
begin
  FIndex := nil;
end;

procedure TTypeInfoClassesTests.ReadsSwitchDirectives;
var
  mValue: Boolean;
begin
  Assert.IsTrue(TTypeInfoClasses.ReadSwitch('{$M+}', mValue) and mValue);
  Assert.IsTrue(TTypeInfoClasses.ReadSwitch('{$M-}', mValue) and not mValue);
  Assert.IsTrue(TTypeInfoClasses.ReadSwitch('{$TYPEINFO ON}', mValue) and mValue);
  Assert.IsTrue(TTypeInfoClasses.ReadSwitch('{$typeinfo off}', mValue) and not mValue);
  Assert.IsTrue(TTypeInfoClasses.ReadSwitch('{$R-,M+,H+}', mValue) and mValue);
  Assert.IsTrue(TTypeInfoClasses.ReadSwitch('(*$M+*)', mValue) and mValue);
  // Stapelgröße und andere Schalter setzen nichts.
  Assert.IsFalse(TTypeInfoClasses.ReadSwitch('{$M 16384,1048576}', mValue));
  Assert.IsFalse(TTypeInfoClasses.ReadSwitch('{$R+}', mValue));
  Assert.IsFalse(TTypeInfoClasses.ReadSwitch('{ M+ }', mValue));
end;

procedure TTypeInfoClassesTests.SwitchFollowsPositionAndConditionals;
const
  cCode =
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
  Assert.IsFalse(TTypeInfoClasses.SwitchAt(cCode, TTextPosition.Create(0, 0)));
  Assert.IsTrue(TTypeInfoClasses.SwitchAt(cCode, TTextPosition.Create(2, 5)));
  Assert.IsFalse(TTypeInfoClasses.SwitchAt(cCode, TTextPosition.Create(4, 5)));
  Assert.IsFalse(TTypeInfoClasses.SwitchAt(cCode, TTextPosition.Create(6, 5)), 'inaktiver Zweig');
  Assert.IsTrue(TTypeInfoClasses.SwitchAt(cCode, TTextPosition.Create(8, 5)), 'aktiver Zweig');
end;

procedure TTypeInfoClassesTests.SwitchFollowsPushAndPopOpt;
const
  cCode =
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
  Assert.IsFalse(TTypeInfoClasses.SwitchAt(cCode, TTextPosition.Create(4, 5)));
  Assert.IsTrue(TTypeInfoClasses.SwitchAt(cCode, TTextPosition.Create(6, 5)));
  // {$POPOPT} ohne {$PUSHOPT} ändert nichts.
  Assert.IsTrue(TTypeInfoClasses.SwitchAt(cCode, TTextPosition.Create(8, 5)));
end;

procedure TTypeInfoClassesTests.FollowsAncestorsThroughIndex;
var
  mClasses: TTypeInfoClasses;
begin
  mClasses := TTypeInfoClasses.Create(FIndex, ReadSource);
  try
    Assert.IsFalse(mClasses.HasTypeInfo('TSchlicht'));
    Assert.IsTrue(mClasses.HasTypeInfo('TMitRtti'), '{$M+} bei der Deklaration');
    Assert.IsTrue(mClasses.HasTypeInfo('TErbe'), 'Vorfahr mit {$M+}');
    Assert.IsTrue(mClasses.HasTypeInfo('Basis.TEnkel'), 'über zwei Stufen, qualifiziert');
    Assert.IsFalse(mClasses.HasTypeInfo('TOhne'));
    Assert.IsFalse(mClasses.HasTypeInfo('TZyklusA'), 'Zyklus bricht ab');
    Assert.IsFalse(mClasses.HasTypeInfo('TObject'));
    Assert.IsFalse(mClasses.HasTypeInfo('TUnbekannt'));
    // Nicht im Index, aber bekannt.
    Assert.IsTrue(mClasses.HasTypeInfo('Vcl.Forms.TForm'));
  finally
    mClasses.Free;
  end;
end;

procedure TTypeInfoClassesTests.KnownClassesWithoutIndex;
var
  mClasses: TTypeInfoClasses;
begin
  Assert.IsTrue(TTypeInfoClasses.KnownTypeInfoClass('TPersistent'));
  Assert.IsTrue(TTypeInfoClasses.KnownTypeInfoClass('TFrame'));
  Assert.IsTrue(TTypeInfoClasses.KnownTypeInfoClass('System.Classes.TComponent'));
  Assert.IsFalse(TTypeInfoClasses.KnownTypeInfoClass('TInterfacedObject'));
  Assert.IsFalse(TTypeInfoClasses.KnownTypeInfoClass('Exception'));
  Assert.IsFalse(TTypeInfoClasses.KnownTypeInfoClass('TList'));
  mClasses := TTypeInfoClasses.Create(nil, nil);
  try
    Assert.IsTrue(mClasses.HasTypeInfo('TDataModule'));
    Assert.IsFalse(mClasses.HasTypeInfo('TMitRtti'), 'ohne Index unbekannt');
  finally
    mClasses.Free;
  end;
end;

function VisibilityOf(const ASymbols: TJSONArray; const AName: string): string;
var
  mItem: TJSONValue;
  mEntry: TJSONObject;
  mChildren: TJSONValue;
begin
  Result := '';
  for mItem in ASymbols do
  begin
    mEntry := mItem as TJSONObject;
    if (mEntry.GetValue<string>('name', '') = AName) and (mEntry.GetValue('atlas') is TJSONObject) then
    begin
      Exit(TJSONObject(mEntry.GetValue('atlas')).GetValue<string>('visibility', ''));
    end;
    mChildren := mEntry.GetValue('children');
    if mChildren is TJSONArray then
    begin
      Result := VisibilityOf(TJSONArray(mChildren), AName);
      if Result <> '' then
      begin
        Exit;
      end;
    end;
  end;
end;

procedure TTypeInfoClassesTests.OutlineUsesTypeInfoForDefaultVisibility;
const
  cCode =
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
  mTree: TSyntaxTree;
  mSymbols: TJSONArray;
begin
  mTree := TPascalParser.Parse(cCode);
  try
    mSymbols := TLspDocumentSymbols.BuildSymbols(mTree, cCode, FIndex, ReadSource);
    try
      Assert.AreEqual('published', VisibilityOf(mSymbols, 'A'), 'Vorfahr im Index mit {$M+}');
      Assert.AreEqual('public', VisibilityOf(mSymbols, 'B'), 'Vorfahr im Index ohne');
      Assert.AreEqual('published', VisibilityOf(mSymbols, 'C'), '{$M+} in der Datei');
      Assert.AreEqual('published', VisibilityOf(mSymbols, 'D'), 'Vorfahr in derselben Datei');
      Assert.AreEqual('published', VisibilityOf(mSymbols, 'E'), 'bekannte VCL-Klasse');
      Assert.AreEqual('public', VisibilityOf(mSymbols, 'F'));
    finally
      mSymbols.Free;
    end;
    // Ohne Index: nur Datei und bekannte Klassen.
    mSymbols := TLspDocumentSymbols.BuildSymbols(mTree, cCode);
    try
      Assert.AreEqual('public', VisibilityOf(mSymbols, 'A'));
      Assert.AreEqual('published', VisibilityOf(mSymbols, 'D'));
      Assert.AreEqual('published', VisibilityOf(mSymbols, 'E'));
    finally
      mSymbols.Free;
    end;
  finally
    mTree.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTypeInfoClassesTests);

end.
