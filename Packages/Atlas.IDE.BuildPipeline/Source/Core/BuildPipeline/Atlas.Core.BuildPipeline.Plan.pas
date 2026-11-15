unit Atlas.Core.BuildPipeline.Plan;

// Entscheidungen der Build-Pipeline in der IDE (#528, #533), ohne VCL und
// Open Tools API. Atlas.IDE.BuildPipeline.Runner, .Gate und .ReleaseGuard
// fragen hier:
// - Ob ein Auftrag von außen abgelehnt wird (eigener Build läuft, fremder
//   Build, Debugger, Art des Builds) und warum.
// - Welche Dateien der Wächter als Quelltext zählt.
// - Regel-IDs ohne Doppelte und welche Konfiguration der Befehl
//   „Release prüfen“ nimmt.

{$SCOPEDENUMS ON}

interface

uses
  System.SysUtils,
  Atlas.Core.Build.Events;

type
  /// <summary>Grund, aus dem ein Auftrag nicht gebaut wird.</summary>
  TAtlasBuildRefusal = (
    /// <summary>Kein Grund: bauen.</summary>
    None,
    /// <summary>Ein eigener Auftrag läuft.</summary>
    Busy,
    /// <summary>Die IDE baut gerade selbst (auch im Hintergrund).</summary>
    ForeignBuild,
    /// <summary>Ein Programm läuft im Debugger.</summary>
    Debugging,
    /// <summary>Art des Builds nicht erlaubt (nur Make, Build, Check).</summary>
    Kind);

  TAtlasBuildPipelinePlan = record
  public
    /// <summary>Grund der Ablehnung in dieser Reihenfolge: eigener Auftrag, fremder Build, Debugger, Art.</summary>
    class function Refusal(ABusy, AForeignBuild, ADebugging: Boolean; AKind: TAtlasCompileKind): TAtlasBuildRefusal;
      static;
    /// <summary>Zählt der Wächter AFileName als Quelltext (.pas, .dpr, .dpk)?</summary>
    class function IsPascalFile(const AFileName: string): Boolean; static;
    /// <summary>ARules ohne Doppelte, in der Reihenfolge des ersten Auftretens.</summary>
    class function UniqueRules(const ARules: TArray<string>): TArray<string>; static;
    /// <summary>Konfiguration für „Release prüfen“: ACurrent, wenn Release (AIsRelease); sonst AReleaseName unter
    /// AConfigurations, sonst die erste Release-Konfiguration; '' ohne.</summary>
    class function CheckConfiguration(const ACurrent: string; const AConfigurations: TArray<string>;
      const AReleaseName: string; const AIsRelease: TFunc<string, Boolean>): string; static;
  end;

implementation

{ TAtlasBuildPipelinePlan }

class function TAtlasBuildPipelinePlan.Refusal(ABusy, AForeignBuild, ADebugging: Boolean;
  AKind: TAtlasCompileKind): TAtlasBuildRefusal;
begin
  if ABusy then
  begin
    Result := TAtlasBuildRefusal.Busy;
  end
  else if AForeignBuild then
  begin
    Result := TAtlasBuildRefusal.ForeignBuild;
  end
  else if ADebugging then
  begin
    Result := TAtlasBuildRefusal.Debugging;
  end
  else if not (AKind in [TAtlasCompileKind.Make, TAtlasCompileKind.Build, TAtlasCompileKind.Check]) then
  begin
    Result := TAtlasBuildRefusal.Kind;
  end
  else
  begin
    Result := TAtlasBuildRefusal.None;
  end;
end;

class function TAtlasBuildPipelinePlan.IsPascalFile(const AFileName: string): Boolean;
var
  mExtension: string;
begin
  mExtension := LowerCase(ExtractFileExt(AFileName));
  Result := (mExtension = '.pas') or (mExtension = '.dpr') or (mExtension = '.dpk');
end;

class function TAtlasBuildPipelinePlan.UniqueRules(const ARules: TArray<string>): TArray<string>;
var
  mRule, mKnown: string;
  mSeen: Boolean;
begin
  Result := nil;
  for mRule in ARules do
  begin
    mSeen := False;
    for mKnown in Result do
    begin
      if mKnown = mRule then
      begin
        mSeen := True;
      end;
    end;
    if not mSeen then
    begin
      Result := Result + [mRule];
    end;
  end;
end;

class function TAtlasBuildPipelinePlan.CheckConfiguration(const ACurrent: string;
  const AConfigurations: TArray<string>; const AReleaseName: string; const AIsRelease: TFunc<string, Boolean>): string;
var
  mName: string;
begin
  if AIsRelease(ACurrent) then
  begin
    Exit(ACurrent);
  end;
  for mName in AConfigurations do
  begin
    if SameText(mName, AReleaseName) then
    begin
      Exit(mName);
    end;
  end;
  for mName in AConfigurations do
  begin
    if AIsRelease(mName) then
    begin
      Exit(mName);
    end;
  end;
  Result := '';
end;

end.
