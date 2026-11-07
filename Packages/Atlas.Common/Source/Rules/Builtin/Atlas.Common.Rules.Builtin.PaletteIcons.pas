unit Atlas.Common.Rules.Builtin.PaletteIcons;

// Palettensymbole registrierter Komponenten (#114): Jede Klasse aus RegisterComponents braucht in
// einer per {$R …} eingebundenen .dcr/.res eine Ressource mit dem Klassennamen in Großbuchstaben.
// Ab Delphi 11 (BDS 22.0) zusätzlich die Größen 16, 24 und 32 px als NAME16, NAME24, NAME32
// (auch NAME_16 usw.); der Name ohne Zusatz gilt als 24 px.
// Ohne eingebundene oder lesbare Ressourcendatei schweigt die Regel: Die .dcr kann im Package
// stecken, das die Regel nicht sieht.

interface

uses
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

type
  TPaletteIconRule = class(TInterfacedObject, IRule)
  private
    class function ReadResourceNames(const AContext: TRuleContext; const ATokens: TArray<TPascalToken>;
      out ANames: TArray<string>): Boolean; static;
    class procedure CheckRegistration(const AContext: TRuleContext; const ATokens: TArray<TPascalToken>;
      const ANames: TArray<string>; const AIndex: Integer; const AReport: IRuleReport); static;
    class function IsListedClass(const ATokens: TArray<TPascalToken>; const AIndex: Integer): Boolean; static;
    class procedure CheckClass(const AContext: TRuleContext; const AToken: TPascalToken;
      const ANames: TArray<string>; const AReport: IRuleReport); static;
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
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.ResourceNames,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TPaletteIconsText = (Title, NoIcon, MissingSizes);

const
  cTexts: array[TPaletteIconsText] of TAtlasText = (
    (De: 'Registrierte Komponente ohne Palettensymbol'; En: 'Registered component without palette icon'),
    (De: 'Kein Palettensymbol %s in den eingebundenen Ressourcen'; En: 'No palette icon %s in the linked resources'),
    (De: 'Palettensymbol %s fehlt in %s px (High-DPI)'; En: 'Palette icon %s is missing in %s px (high DPI)'));

{$SCOPEDENUMS OFF}

const
  cHighDpiVersion = 22;

/// <summary>Dateiname aus {$R name.dcr} bzw. {$RESOURCE 'name.res'}; False bei {$R+} und anderen.</summary>
function ResourceFile(const ADirective, AUnitName: string; out AFileName: string): Boolean;
var
  mText: string;
begin
  Result := False;
  mText := Trim(ADirective);
  if not (StartsText('{$R ', mText) or StartsText('{$RESOURCE ', mText)) or not EndsText('}', mText) then
  begin
    Exit;
  end;
  mText := Trim(Copy(mText, Pos(' ', mText) + 1, Length(mText) - Pos(' ', mText) - 1));
  // {$R 'a.res' 'a.rc'}: nur die erste Angabe.
  if StartsText('''', mText) then
  begin
    mText := Copy(mText, 2, Pos('''', Copy(mText, 2, MaxInt)) - 1);
  end
  else if Pos(' ', mText) > 0 then
  begin
    mText := Copy(mText, 1, Pos(' ', mText) - 1);
  end;
  if not (EndsText('.dcr', mText) or EndsText('.res', mText)) then
  begin
    Exit;
  end;
  if StartsText('*', mText) then
  begin
    if AUnitName = '' then
    begin
      Exit;
    end;
    mText := AUnitName + Copy(mText, 2, MaxInt);
  end;
  AFileName := mText;
  Result := True;
end;

function MajorVersion(const AVersion: string): Integer;
var
  mText: string;
begin
  mText := AVersion;
  if Pos('.', mText) > 0 then
  begin
    mText := Copy(mText, 1, Pos('.', mText) - 1);
  end;
  Result := StrToIntDef(mText, 0);
end;

function HasName(const ANames: TArray<string>; const AName: string): Boolean;
begin
  Result := IndexText(AName, ANames) >= 0;
end;

function HasSize(const ANames: TArray<string>; const AName, ASize: string): Boolean;
begin
  Result := HasName(ANames, AName + ASize) or HasName(ANames, AName + '_' + ASize);
end;

/// <summary>True, wenn der Name ohne Zusatz oder in einer der Größen 16, 24, 32 vorkommt.</summary>
function HasAnyIcon(const ANames: TArray<string>; const AName: string): Boolean;
begin
  Result := HasName(ANames, AName) or HasSize(ANames, AName, '16') or HasSize(ANames, AName, '24') or
    HasSize(ANames, AName, '32');
end;

/// <summary>Fehlende High-DPI-Größen, durch Komma getrennt; der Name ohne Zusatz gilt als 24 px.</summary>
function MissingSizes(const ANames: TArray<string>; const AName: string): string;
var
  mSize: string;
begin
  Result := '';
  for mSize in TArray<string>.Create('16', '24', '32') do
  begin
    if not HasSize(ANames, AName, mSize) and not ((mSize = '24') and HasName(ANames, AName)) then
    begin
      Result := Result + IfThen(Result <> '', ', ') + mSize;
    end;
  end;
end;

{ TPaletteIconRule }

function TPaletteIconRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('component-palette-icon', TRuleSeverity.Hint,
    cTexts[TPaletteIconsText.Title].Text);
end;

procedure TPaletteIconRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mTokens: TArray<TPascalToken>;
  mNames: TArray<string>;
  mIndex: Integer;
begin
  if (AContext.Tree = nil) or not Assigned(AContext.ReadFile) then
  begin
    Exit;
  end;
  mTokens := AContext.Tree.Tokens;
  if not ReadResourceNames(AContext, mTokens, mNames) then
  begin
    Exit;
  end;
  for mIndex := 0 to High(mTokens) do
  begin
    if (mTokens[mIndex].Kind = TPascalTokenKind.Identifier) and
      SameText(mTokens[mIndex].Text, 'RegisterComponents') then
    begin
      CheckRegistration(AContext, mTokens, mNames, mIndex, AReport);
    end;
  end;
end;

class function TPaletteIconRule.ReadResourceNames(const AContext: TRuleContext;
  const ATokens: TArray<TPascalToken>; out ANames: TArray<string>): Boolean;
var
  mData: TBytes;
  mFileName: string;
  mIndex: Integer;
begin
  Result := False;
  ANames := nil;
  for mIndex := 0 to High(ATokens) do
  begin
    if (ATokens[mIndex].Kind = TPascalTokenKind.Directive) and
      ResourceFile(ATokens[mIndex].Text, AContext.UnitName, mFileName) and AContext.ReadFile(mFileName, mData) then
    begin
      Result := True;
      ANames := ANames + TResourceNames.Read(mData);
    end;
  end;
end;

class procedure TPaletteIconRule.CheckRegistration(const AContext: TRuleContext;
  const ATokens: TArray<TPascalToken>; const ANames: TArray<string>; const AIndex: Integer;
  const AReport: IRuleReport);
var
  mInner, mDepth: Integer;
begin
  // RegisterComponents('Seite', [TA, Einheit.TB]): Bezeichner direkt vor , oder ] in der Klammer.
  mInner := AIndex + 1;
  while (mInner <= High(ATokens)) and not ATokens[mInner].IsSymbol('[') and not ATokens[mInner].IsSymbol(';') do
  begin
    Inc(mInner);
  end;
  mDepth := 0;
  while mInner <= High(ATokens) do
  begin
    if ATokens[mInner].IsSymbol('[') or ATokens[mInner].IsSymbol('(') then
    begin
      Inc(mDepth);
    end
    else if ATokens[mInner].IsSymbol(']') or ATokens[mInner].IsSymbol(')') then
    begin
      Dec(mDepth);
    end;
    if (mDepth = 0) or ATokens[mInner].IsSymbol(';') then
    begin
      Break;
    end;
    if (mDepth = 1) and IsListedClass(ATokens, mInner) then
    begin
      CheckClass(AContext, ATokens[mInner], ANames, AReport);
    end;
    Inc(mInner);
  end;
end;

class function TPaletteIconRule.IsListedClass(const ATokens: TArray<TPascalToken>;
  const AIndex: Integer): Boolean;
begin
  Result := (ATokens[AIndex].Kind = TPascalTokenKind.Identifier) and (AIndex < High(ATokens)) and
    (ATokens[AIndex + 1].IsSymbol(',') or ATokens[AIndex + 1].IsSymbol(']'));
end;

class procedure TPaletteIconRule.CheckClass(const AContext: TRuleContext; const AToken: TPascalToken;
  const ANames: TArray<string>; const AReport: IRuleReport);
var
  mUpper, mMissing: string;
begin
  mUpper := UpperCase(AToken.Text);
  if not HasAnyIcon(ANames, mUpper) then
  begin
    AReport.Add(TTextRange.Create(AToken.StartPos, AToken.EndPos),
      cTexts[TPaletteIconsText.NoIcon].Fmt([mUpper]));
    Exit;
  end;
  if MajorVersion(AContext.DelphiVersion) < cHighDpiVersion then
  begin
    Exit;
  end;
  mMissing := MissingSizes(ANames, mUpper);
  if mMissing <> '' then
  begin
    AReport.Add(TTextRange.Create(AToken.StartPos, AToken.EndPos),
      cTexts[TPaletteIconsText.MissingSizes].Fmt([mUpper, mMissing]));
  end;
end;

procedure RegisterPaletteIconRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TPaletteIconRule.Create);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.PaletteIcons', cTexts);

end.
