unit Atlas.Common.Rules.Builtin.PaletteIcons.Tests;

// Tests für Palettensymbole (#114): Ressourcennamen aus .res/.dcr und die Regel component-palette-icon.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TPaletteIconTests = class
  public
    [Test]
    procedure ReadsResourceNames;
    [Test]
    procedure BrokenDataKeepsReadNames;
    [Test]
    procedure MissingIconReported;
    [Test]
    procedure IconPresentSilent;
    [Test]
    procedure WithoutResourceDirectiveSilent;
    [Test]
    procedure MissingSizesFromDelphi11;
    [Test]
    procedure AllSizesSilent;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Engine,
  Atlas.Common.Rules.ResourceNames,
  Atlas.Common.Rules.Builtin.PaletteIcons;

const
  cRegisterUnit =
    'unit Comps;'#10'interface'#10'procedure Register;'#10'implementation'#10'%s'#10 +
    'procedure Register;'#10'begin'#10'  RegisterComponents(''Eigene'', [TKnopf, Comps.TLeiste]);'#10'end;'#10'end.';

procedure AddWord(var AData: TBytes; AValue: Integer);
begin
  AData := AData + [Byte(AValue and $FF), Byte((AValue shr 8) and $FF)];
end;

procedure AddCardinal(var AData: TBytes; AValue: Integer);
begin
  AddWord(AData, AValue and $FFFF);
  AddWord(AData, (AValue shr 16) and $FFFF);
end;

/// <summary>Ressourcendatei mit leerem Kopfeintrag und je einer Bitmap (2 Byte Daten) je Name.</summary>
function ResFile(const ANames: array of string): TBytes;
var
  mName: string;
  mHeader: TBytes;
  mIndex: Integer;
begin
  Result := nil;
  AddCardinal(Result, 0);
  AddCardinal(Result, 32);
  for mIndex := 1 to 6 do
  begin
    AddCardinal(Result, $0000FFFF * Ord(mIndex <= 2));
  end;
  for mName in ANames do
  begin
    mHeader := nil;
    AddWord(mHeader, $FFFF);
    AddWord(mHeader, 2);
    for mIndex := 1 to Length(mName) do
    begin
      AddWord(mHeader, Ord(mName[mIndex]));
    end;
    AddWord(mHeader, 0);
    while (Length(mHeader) + 8) mod 4 <> 0 do
    begin
      AddWord(mHeader, 0);
    end;
    for mIndex := 1 to 4 do
    begin
      AddCardinal(mHeader, 0);
    end;
    AddCardinal(Result, 2);
    AddCardinal(Result, Length(mHeader) + 8);
    Result := Result + mHeader + [1, 2, 0, 0];
  end;
end;

function Run(const ASource, AVersion: string; const AFiles: array of string): TArray<TRuleFinding>;
var
  mContext: TRuleContext;
  mTree: TSyntaxTree;
  mData: TBytes;
begin
  mData := ResFile(AFiles);
  mTree := TPascalParser.Parse(ASource);
  try
    mContext := Default(TRuleContext);
    mContext.UnitName := 'Comps';
    mContext.Text := ASource;
    mContext.Tree := mTree;
    mContext.DelphiVersion := AVersion;
    mContext.ReadFile :=
      function(const AName: string; out AData: TBytes): Boolean
      begin
        Result := SameText(AName, 'Comps.dcr');
        AData := mData;
      end;
    Result := TRuleEngine.Run([TPaletteIconRule.Create], TServerSettings.Default, mContext);
  finally
    mTree.Free;
  end;
end;

function Source(const ADirective: string): string;
begin
  Result := StringReplace(cRegisterUnit, '%s', ADirective, []);
end;

procedure TPaletteIconTests.ReadsResourceNames;
var
  mNames: TArray<string>;
begin
  mNames := TResourceNames.Read(ResFile(['TKnopf', 'tleiste16']));
  Assert.AreEqual(2, Integer(Length(mNames)));
  Assert.AreEqual('TKNOPF', mNames[0]);
  Assert.AreEqual('TLEISTE16', mNames[1]);
end;

procedure TPaletteIconTests.BrokenDataKeepsReadNames;
var
  mData: TBytes;
begin
  mData := ResFile(['TKNOPF', 'TLEISTE']);
  SetLength(mData, Length(mData) - 3);
  Assert.AreEqual(1, Integer(Length(TResourceNames.Read(mData))));
  Assert.AreEqual(0, Integer(Length(TResourceNames.Read(TBytes.Create(1, 2, 3)))));
end;

procedure TPaletteIconTests.MissingIconReported;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := Run(Source('{$R *.dcr}'), '', ['TKNOPF']);
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.IsTrue(Pos('TLEISTE', mFindings[0].Message) > 0, mFindings[0].Message);
  Assert.AreEqual(7, mFindings[0].Range.StartPos.Line);
end;

procedure TPaletteIconTests.IconPresentSilent;
begin
  Assert.AreEqual(0, Integer(Length(Run(Source('{$R Comps.dcr}'), '', ['TKNOPF', 'TLEISTE']))));
  Assert.AreEqual(0, Integer(Length(Run(Source('{$RESOURCE ''Comps.dcr''}'), '21.0', ['tknopf', 'TLEISTE']))));
end;

procedure TPaletteIconTests.WithoutResourceDirectiveSilent;
begin
  // {$R+} ist die Bereichsprüfung, keine Ressource; die .dcr kann dann im Package stecken.
  Assert.AreEqual(0, Integer(Length(Run(Source('{$R+}'), '', []))));
  Assert.AreEqual(0, Integer(Length(Run(Source('{$R Andere.dcr}'), '', []))));
end;

procedure TPaletteIconTests.MissingSizesFromDelphi11;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := Run(Source('{$R *.dcr}'), '22.0', ['TKNOPF', 'TKNOPF16', 'TKNOPF32', 'TLEISTE']);
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.IsTrue(Pos('TLEISTE fehlt in 16, 32 px', mFindings[0].Message) > 0, mFindings[0].Message);
end;

procedure TPaletteIconTests.AllSizesSilent;
begin
  Assert.AreEqual(0, Integer(Length(Run(Source('{$R *.dcr}'), '37.0',
    ['TKNOPF16', 'TKNOPF24', 'TKNOPF32', 'TLEISTE', 'TLEISTE_16', 'TLEISTE_32']))));
end;

initialization
  TDUnitX.RegisterTestFixture(TPaletteIconTests);

end.
