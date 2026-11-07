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
  mCheck: TAtlasReleaseCheck;
begin
  for mCheck := Low(TAtlasReleaseCheck) to High(TAtlasReleaseCheck) do
  begin
    Result.Items[mCheck].Enabled := True;
    Result.Items[mCheck].Expected := False;
  end;
end;

function CheckOf(const AName: string; out ACheck: TAtlasReleaseCheck): Boolean;
var
  mCheck: TAtlasReleaseCheck;
begin
  for mCheck := Low(TAtlasReleaseCheck) to High(TAtlasReleaseCheck) do
  begin
    if SameText(AName, TAtlasBuildPipelineSettings.CheckNames[mCheck]) then
    begin
      ACheck := mCheck;
      Exit(True);
    end;
  end;
  ACheck := TAtlasReleaseCheck.DebugDefine;
  Result := False;
end;

class function TAtlasReleaseChecks.Parse(const AText: string): TAtlasReleaseChecks;
var
  mPart, mName, mTarget: string;
  mEnabled: Boolean;
  mEquals: Integer;
  mCheck: TAtlasReleaseCheck;
begin
  Result := Defaults;
  for mPart in AText.Split([',', ';']) do
  begin
    mName := Trim(mPart);
    mEnabled := True;
    if mName.StartsWith('-') or mName.StartsWith('!') then
    begin
      mEnabled := False;
      mName := Trim(Copy(mName, 2, MaxInt));
    end;
    mTarget := '';
    mEquals := Pos('=', mName);
    if mEquals > 0 then
    begin
      mTarget := Trim(Copy(mName, mEquals + 1, MaxInt));
      mName := Trim(Copy(mName, 1, mEquals - 1));
    end;
    if not CheckOf(mName, mCheck) then
    begin
      Continue;
    end;
    Result.Items[mCheck].Enabled := mEnabled;
    if TAtlasBuildPipelineSettings.HasTarget[mCheck] and (mTarget <> '') then
    begin
      Result.Items[mCheck].Expected := SameText(mTarget, 'on') or SameText(mTarget, 'true') or (mTarget = '1');
    end;
  end;
end;

function TAtlasReleaseChecks.ToText: string;
const
  cTargets: array[Boolean] of string = ('=off', '=on');
var
  mCheck: TAtlasReleaseCheck;
  mItem: string;
begin
  Result := '';
  for mCheck := Low(TAtlasReleaseCheck) to High(TAtlasReleaseCheck) do
  begin
    mItem := TAtlasBuildPipelineSettings.CheckNames[mCheck];
    if not Items[mCheck].Enabled then
    begin
      mItem := '-' + mItem;
    end;
    if TAtlasBuildPipelineSettings.HasTarget[mCheck] then
    begin
      mItem := mItem + cTargets[Items[mCheck].Expected];
    end;
    if Result <> '' then
    begin
      Result := Result + ',';
    end;
    Result := Result + mItem;
  end;
end;

class function TAtlasReleaseChecks.Normalized(const AText: string): string;
begin
  Result := Parse(AText).ToText;
end;

class function TAtlasBuildPipelineSettings.GateOf(const AText: string): TAtlasBuildGate;
var
  mGate: TAtlasBuildGate;
begin
  for mGate := Low(TAtlasBuildGate) to High(TAtlasBuildGate) do
  begin
    if SameText(Trim(AText), GateNames[mGate]) then
    begin
      Exit(mGate);
    end;
  end;
  Result := TAtlasBuildGate.Off;
end;

class function TAtlasBuildPipelineSettings.ConfigurationList(const AText: string): TArray<string>;
var
  mPart, mName, mKnown: string;
  mSeen: Boolean;
begin
  Result := nil;
  for mPart in AText.Split([',', ';']) do
  begin
    mName := Trim(mPart);
    // JSON-artige Eingabe ["Release", "Ship"] verträgt die Liste auch.
    mName := Trim(StringReplace(StringReplace(StringReplace(mName, '"', '', [rfReplaceAll]), '[', '',
      [rfReplaceAll]), ']', '', [rfReplaceAll]));
    if mName = '' then
    begin
      Continue;
    end;
    mSeen := False;
    for mKnown in Result do
    begin
      if SameText(mKnown, mName) then
      begin
        mSeen := True;
      end;
    end;
    if not mSeen then
    begin
      Result := Result + [mName];
    end;
  end;
end;

class function TAtlasBuildPipelineSettings.NormalizedConfigurations(const AText: string): string;
begin
  Result := string.Join(', ', ConfigurationList(AText));
end;

end.
