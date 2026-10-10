unit Argus.Common.Rules.Builtin.PaletteIcons.Tests;

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
  Argus.Common.Configuration.Contract,
  Argus.Common.Pascal.SyntaxTree,
  Argus.Common.Pascal.Parser,
  Argus.Common.Rules.Contract,
  Argus.Common.Rules.Engine,
  Argus.Common.Rules.ResourceNames,
  Argus.Common.Rules.Builtin.PaletteIcons;

const
  RegisterUnit =
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
  Name: string;
  Header: TBytes;
  Index: Integer;
begin
  Result := nil;
  AddCardinal(Result, 0);
  AddCardinal(Result, 32);
  for Index := 1 to 6 do
    AddCardinal(Result, $0000FFFF * Ord(Index <= 2));
  for Name in ANames do
  begin
    Header := nil;
    AddWord(Header, $FFFF);
    AddWord(Header, 2);
    for Index := 1 to Length(Name) do
      AddWord(Header, Ord(Name[Index]));
    AddWord(Header, 0);
    while (Length(Header) + 8) mod 4 <> 0 do
      AddWord(Header, 0);
    for Index := 1 to 4 do
      AddCardinal(Header, 0);
    AddCardinal(Result, 2);
    AddCardinal(Result, Length(Header) + 8);
    Result := Result + Header + [1, 2, 0, 0];
  end;
end;

function Run(const ASource, AVersion: string; const AFiles: array of string): TArray<TRuleFinding>;
var
  Context: TRuleContext;
  Tree: TSyntaxTree;
  Data: TBytes;
begin
  Data := ResFile(AFiles);
  Tree := TPascalParser.Parse(ASource);
  try
    Context := Default(TRuleContext);
    Context.UnitName := 'Comps';
    Context.Text := ASource;
    Context.Tree := Tree;
    Context.DelphiVersion := AVersion;
    Context.ReadFile :=
      function(const AName: string; out AData: TBytes): Boolean
      begin
        Result := SameText(AName, 'Comps.dcr');
        AData := Data;
      end;
    Result := TRuleEngine.Run([TPaletteIconRule.Create], TServerSettings.Default, Context);
  finally
    Tree.Free;
  end;
end;

function Source(const ADirective: string): string;
begin
  Result := StringReplace(RegisterUnit, '%s', ADirective, []);
end;

procedure TPaletteIconTests.ReadsResourceNames;
var
  Names: TArray<string>;
begin
  Names := TResourceNames.Read(ResFile(['TKnopf', 'tleiste16']));
  Assert.AreEqual(2, Integer(Length(Names)));
  Assert.AreEqual('TKNOPF', Names[0]);
  Assert.AreEqual('TLEISTE16', Names[1]);
end;

procedure TPaletteIconTests.BrokenDataKeepsReadNames;
var
  Data: TBytes;
begin
  Data := ResFile(['TKNOPF', 'TLEISTE']);
  SetLength(Data, Length(Data) - 3);
  Assert.AreEqual(1, Integer(Length(TResourceNames.Read(Data))));
  Assert.AreEqual(0, Integer(Length(TResourceNames.Read(TBytes.Create(1, 2, 3)))));
end;

procedure TPaletteIconTests.MissingIconReported;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := Run(Source('{$R *.dcr}'), '', ['TKNOPF']);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.IsTrue(Pos('TLEISTE', Findings[0].Message) > 0, Findings[0].Message);
  Assert.AreEqual(7, Findings[0].Range.StartPos.Line);
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
  Findings: TArray<TRuleFinding>;
begin
  Findings := Run(Source('{$R *.dcr}'), '22.0', ['TKNOPF', 'TKNOPF16', 'TKNOPF32', 'TLEISTE']);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.IsTrue(Pos('TLEISTE fehlt in 16, 32 px', Findings[0].Message) > 0, Findings[0].Message);
end;

procedure TPaletteIconTests.AllSizesSilent;
begin
  Assert.AreEqual(0, Integer(Length(Run(Source('{$R *.dcr}'), '37.0',
    ['TKNOPF16', 'TKNOPF24', 'TKNOPF32', 'TLEISTE', 'TLEISTE_16', 'TLEISTE_32']))));
end;

initialization
  TDUnitX.RegisterTestFixture(TPaletteIconTests);

end.
