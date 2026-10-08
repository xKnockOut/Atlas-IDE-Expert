unit BDLsp.Common.Rules.Builtin.PaletteIcons;

// Palettensymbole registrierter Komponenten (#114): Jede Klasse aus RegisterComponents braucht in
// einer per {$R …} eingebundenen .dcr/.res eine Ressource mit dem Klassennamen in Großbuchstaben.
// Ab Delphi 11 (BDS 22.0) zusätzlich die Größen 16, 24 und 32 px als NAME16, NAME24, NAME32
// (auch NAME_16 usw.); der Name ohne Zusatz gilt als 24 px.
// Ohne eingebundene oder lesbare Ressourcendatei schweigt die Regel: Die .dcr kann im Package
// stecken, das die Regel nicht sieht.

interface

uses
  BDLsp.Common.Rules.Contract,
  BDLsp.Common.Rules.Registry;

type
  TPaletteIconRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

/// <summary>Registriert die Regel für Palettensymbole.</summary>
procedure RegisterPaletteIconRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.SysUtils,
  System.StrUtils,
  BDLsp.Common.Documents.Contract,
  BDLsp.Common.Configuration.Contract,
  BDLsp.Common.Pascal.Contract,
  BDLsp.Common.Rules.ResourceNames;

const
  HighDpiVersion = 22;

/// <summary>Dateiname aus {$R name.dcr} bzw. {$RESOURCE 'name.res'}; False bei {$R+} und anderen.</summary>
function ResourceFile(const ADirective, AUnitName: string; out AFileName: string): Boolean;
var
  Text: string;
begin
  Result := False;
  Text := Trim(ADirective);
  if not (StartsText('{$R ', Text) or StartsText('{$RESOURCE ', Text)) or not EndsText('}', Text) then
    Exit;
  Text := Trim(Copy(Text, Pos(' ', Text) + 1, Length(Text) - Pos(' ', Text) - 1));
  // {$R 'a.res' 'a.rc'}: nur die erste Angabe.
  if StartsText('''', Text) then
    Text := Copy(Text, 2, Pos('''', Copy(Text, 2, MaxInt)) - 1)
  else if Pos(' ', Text) > 0 then
    Text := Copy(Text, 1, Pos(' ', Text) - 1);
  if not (EndsText('.dcr', Text) or EndsText('.res', Text)) then
    Exit;
  if StartsText('*', Text) then
  begin
    if AUnitName = '' then
      Exit;
    Text := AUnitName + Copy(Text, 2, MaxInt);
  end;
  AFileName := Text;
  Result := True;
end;

function MajorVersion(const AVersion: string): Integer;
var
  Text: string;
begin
  Text := AVersion;
  if Pos('.', Text) > 0 then
    Text := Copy(Text, 1, Pos('.', Text) - 1);
  Result := StrToIntDef(Text, 0);
end;

function HasName(const ANames: TArray<string>; const AName: string): Boolean;
begin
  Result := IndexText(AName, ANames) >= 0;
end;

function HasSize(const ANames: TArray<string>; const AName, ASize: string): Boolean;
begin
  Result := HasName(ANames, AName + ASize) or HasName(ANames, AName + '_' + ASize);
end;

{ TPaletteIconRule }

function TPaletteIconRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('component-palette-icon', TRuleSeverity.Hint,
    'Registrierte Komponente ohne Palettensymbol');
end;

procedure TPaletteIconRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TArray<TPascalToken>;
  Names: TArray<string>;
  Data: TBytes;
  FileName, Upper, Missing, Size: string;
  Index, Inner, Depth: Integer;
  Found: Boolean;
begin
  if (AContext.Tree = nil) or not Assigned(AContext.ReadFile) then
    Exit;
  Tokens := AContext.Tree.Tokens;
  Names := nil;
  Found := False;
  for Index := 0 to High(Tokens) do
    if (Tokens[Index].Kind = TPascalTokenKind.Directive) and
      ResourceFile(Tokens[Index].Text, AContext.UnitName, FileName) and AContext.ReadFile(FileName, Data) then
    begin
      Found := True;
      Names := Names + TResourceNames.Read(Data);
    end;
  if not Found then
    Exit;
  for Index := 0 to High(Tokens) do
  begin
    if (Tokens[Index].Kind <> TPascalTokenKind.Identifier) or
      not SameText(Tokens[Index].Text, 'RegisterComponents') then
      Continue;
    // RegisterComponents('Seite', [TA, Einheit.TB]): Bezeichner direkt vor , oder ] in der Klammer.
    Inner := Index + 1;
    while (Inner <= High(Tokens)) and not Tokens[Inner].IsSymbol('[') and not Tokens[Inner].IsSymbol(';') do
      Inc(Inner);
    Depth := 0;
    while Inner <= High(Tokens) do
    begin
      if Tokens[Inner].IsSymbol('[') or Tokens[Inner].IsSymbol('(') then
        Inc(Depth)
      else if Tokens[Inner].IsSymbol(']') or Tokens[Inner].IsSymbol(')') then
        Dec(Depth);
      if (Depth = 0) or Tokens[Inner].IsSymbol(';') then
        Break;
      if (Depth = 1) and (Tokens[Inner].Kind = TPascalTokenKind.Identifier) and (Inner < High(Tokens)) and
        (Tokens[Inner + 1].IsSymbol(',') or Tokens[Inner + 1].IsSymbol(']')) then
      begin
        Upper := UpperCase(Tokens[Inner].Text);
        if not HasName(Names, Upper) and not HasSize(Names, Upper, '16') and not HasSize(Names, Upper, '24') and
          not HasSize(Names, Upper, '32') then
          AReport.Add(TTextRange.Create(Tokens[Inner].StartPos, Tokens[Inner].EndPos),
            'Kein Palettensymbol ' + Upper + ' in den eingebundenen Ressourcen')
        else if MajorVersion(AContext.DelphiVersion) >= HighDpiVersion then
        begin
          Missing := '';
          for Size in TArray<string>.Create('16', '24', '32') do
            if not HasSize(Names, Upper, Size) and not ((Size = '24') and HasName(Names, Upper)) then
              Missing := Missing + IfThen(Missing <> '', ', ') + Size;
          if Missing <> '' then
            AReport.Add(TTextRange.Create(Tokens[Inner].StartPos, Tokens[Inner].EndPos),
              'Palettensymbol ' + Upper + ' fehlt in ' + Missing + ' px (High-DPI)');
        end;
      end;
      Inc(Inner);
    end;
  end;
end;

procedure RegisterPaletteIconRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TPaletteIconRule.Create);
end;

end.
