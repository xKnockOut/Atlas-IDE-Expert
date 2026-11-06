unit Atlas.Core.Build.PipelineSettings;

// Werte der Einstellungen der Build-Pipeline (#529, #533, #1455), ohne VCL und
// Open Tools API: build.gate, build.gateTimeoutMs, build.releaseConfigs und
// build.releaseChecks. Base: Einstellungen und Optionsdialog lesen und
// schreiben sie, auch ohne das Modul atlas.buildpipeline; Prüfung vor dem
// Kompilieren und Release-Wächter (Modul) werten sie aus.
// Textform von build.releaseChecks: durch Komma getrennt „name“ (an), „-name“
// (aus), mit Sollwert „name=off“ bzw. „name=on“ (auch „-name=on“). Fehlende
// Namen gelten mit ihrer Vorgabe (alle an, Sollwerte aus); unbekannte
// entfallen. Normalized schreibt alle in fester Reihenfolge.

interface

uses
  System.SysUtils;

type
{$SCOPEDENUMS ON}
  /// <summary>Einzeln abschaltbare Prüfung (build.releaseChecks).</summary>
  TAtlasReleaseCheck = (DebugDefine, DebugInfo, StackFrames, Assertions, RangeChecks, OverflowChecks, MemoryLeaks,
    VersionInfo, OutputFolder);
  /// <summary>build.gate (#529): off und warn melden nur, block bricht den Build ab.</summary>
  TAtlasBuildGate = (Off, Warn, Block);
{$SCOPEDENUMS OFF}

  TAtlasReleaseCheckSetting = record
    Enabled: Boolean;
    /// <summary>Sollwert der Compileroption (nur für Prüfungen mit Sollwert): True = an.</summary>
    Expected: Boolean;
  end;

  TAtlasReleaseChecks = record
    Items: array[TAtlasReleaseCheck] of TAtlasReleaseCheckSetting;
    /// <summary>Alle an, Sollwerte aus.</summary>
    class function Defaults: TAtlasReleaseChecks; static;
    /// <summary>Liest die Textform (siehe Kopf); fehlende Namen mit Vorgabe, unbekannte entfallen.</summary>
    class function Parse(const AText: string): TAtlasReleaseChecks; static;
    /// <summary>Textform in fester Reihenfolge mit allen Prüfungen.</summary>
    function ToText: string;
    /// <summary>Parse und ToText in einem: einheitliche Schreibweise für die Ablage.</summary>
    class function Normalized(const AText: string): string; static;
  end;

  TAtlasBuildPipelineSettings = class
  public const
    ReleaseConfiguration = 'Release';
    CheckNames: array[TAtlasReleaseCheck] of string = ('debugDefine', 'debugInfo', 'stackFrames', 'assertions',
      'rangeChecks', 'overflowChecks', 'memoryLeaks', 'versionInfo', 'outputFolder');
    /// <summary>Prüfungen mit Sollwert (Compileroptionen).</summary>
    HasTarget: array[TAtlasReleaseCheck] of Boolean = (False, True, True, True, True, True, False, False, False);
    GateNames: array[TAtlasBuildGate] of string = ('off', 'warn', 'block');
    /// <summary>build.gateTimeoutMs: Vorgabe und Grenzen.</summary>
    GateDefaultTimeoutMs = 300;
    GateMinTimeoutMs = 50;
    GateMaxTimeoutMs = 10000;
  public
    /// <summary>"off", "warn" oder "block" (Groß-/Kleinschreibung egal); sonst off.</summary>
    class function GateOf(const AText: string): TAtlasBuildGate; static;
    /// <summary>Konfigurationen durch Komma oder Semikolon getrennt, ohne Leere und Doppelte; Schreibweise der
    /// ersten Nennung.</summary>
    class function ConfigurationList(const AText: string): TArray<string>; static;
    /// <summary>Einheitliche Schreibweise von build.releaseConfigs: Liste durch ", " getrennt.</summary>
    class function NormalizedConfigurations(const AText: string): string; static;
  end;

implementation

{ TAtlasReleaseChecks }

class function TAtlasReleaseChecks.Defaults: TAtlasReleaseChecks;
var
  Check: TAtlasReleaseCheck;
begin
  for Check := Low(TAtlasReleaseCheck) to High(TAtlasReleaseCheck) do
  begin
    Result.Items[Check].Enabled := True;
    Result.Items[Check].Expected := False;
  end;
end;

function CheckOf(const AName: string; out ACheck: TAtlasReleaseCheck): Boolean;
var
  Check: TAtlasReleaseCheck;
begin
  for Check := Low(TAtlasReleaseCheck) to High(TAtlasReleaseCheck) do
  begin
    if SameText(AName, TAtlasBuildPipelineSettings.CheckNames[Check]) then
    begin
      ACheck := Check;
      Exit(True);
    end;
  end;
  ACheck := TAtlasReleaseCheck.DebugDefine;
  Result := False;
end;

class function TAtlasReleaseChecks.Parse(const AText: string): TAtlasReleaseChecks;
var
  Part, Name, Target: string;
  Enabled: Boolean;
  Equals: Integer;
  Check: TAtlasReleaseCheck;
begin
  Result := Defaults;
  for Part in AText.Split([',', ';']) do
  begin
    Name := Trim(Part);
    Enabled := True;
    if Name.StartsWith('-') or Name.StartsWith('!') then
    begin
      Enabled := False;
      Name := Trim(Copy(Name, 2, MaxInt));
    end;
    Target := '';
    Equals := Pos('=', Name);
    if Equals > 0 then
    begin
      Target := Trim(Copy(Name, Equals + 1, MaxInt));
      Name := Trim(Copy(Name, 1, Equals - 1));
    end;
    if not CheckOf(Name, Check) then
    begin
      Continue;
    end;
    Result.Items[Check].Enabled := Enabled;
    if TAtlasBuildPipelineSettings.HasTarget[Check] and (Target <> '') then
    begin
      Result.Items[Check].Expected := SameText(Target, 'on') or SameText(Target, 'true') or (Target = '1');
    end;
  end;
end;

function TAtlasReleaseChecks.ToText: string;
const
  Targets: array[Boolean] of string = ('=off', '=on');
var
  Check: TAtlasReleaseCheck;
  Item: string;
begin
  Result := '';
  for Check := Low(TAtlasReleaseCheck) to High(TAtlasReleaseCheck) do
  begin
    Item := TAtlasBuildPipelineSettings.CheckNames[Check];
    if not Items[Check].Enabled then
    begin
      Item := '-' + Item;
    end;
    if TAtlasBuildPipelineSettings.HasTarget[Check] then
    begin
      Item := Item + Targets[Items[Check].Expected];
    end;
    if Result <> '' then
    begin
      Result := Result + ',';
    end;
    Result := Result + Item;
  end;
end;

class function TAtlasReleaseChecks.Normalized(const AText: string): string;
begin
  Result := Parse(AText).ToText;
end;

class function TAtlasBuildPipelineSettings.GateOf(const AText: string): TAtlasBuildGate;
var
  Gate: TAtlasBuildGate;
begin
  for Gate := Low(TAtlasBuildGate) to High(TAtlasBuildGate) do
  begin
    if SameText(Trim(AText), GateNames[Gate]) then
    begin
      Exit(Gate);
    end;
  end;
  Result := TAtlasBuildGate.Off;
end;

class function TAtlasBuildPipelineSettings.ConfigurationList(const AText: string): TArray<string>;
var
  Part, Name, Known: string;
  Seen: Boolean;
begin
  Result := nil;
  for Part in AText.Split([',', ';']) do
  begin
    Name := Trim(Part);
    // JSON-artige Eingabe ["Release", "Ship"] verträgt die Liste auch.
    Name := Trim(StringReplace(StringReplace(StringReplace(Name, '"', '', [rfReplaceAll]), '[', '',
      [rfReplaceAll]), ']', '', [rfReplaceAll]));
    if Name = '' then
    begin
      Continue;
    end;
    Seen := False;
    for Known in Result do
    begin
      if SameText(Known, Name) then
      begin
        Seen := True;
      end;
    end;
    if not Seen then
    begin
      Result := Result + [Name];
    end;
  end;
end;

class function TAtlasBuildPipelineSettings.NormalizedConfigurations(const AText: string): string;
begin
  Result := string.Join(', ', ConfigurationList(AText));
end;

end.
