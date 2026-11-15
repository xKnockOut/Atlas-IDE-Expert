unit Atlas.Core.VersionControl.Plan;

// Entscheidungen der Versionsverwaltung in der IDE (#571, #1288), ohne VCL
// und Open Tools API. Atlas.IDE.VersionControl.Service und
// Atlas.IDE.VersionControl.Branching fragen hier:
// - Zeitlimit für Aufrufe, die länger dauern dürfen, und der Zustand eines
//   Projekts ohne Prozess (aus, keine Arbeitskopie, Programm fehlt, bereit).
// - Ort, an dem „Branch anlegen“ nach einem SVN-Branch sucht, und was nach
//   dem Lauf im Hintergrund gemeldet wird.

{$SCOPEDENUMS ON}

interface

uses
  Atlas.Core.VersionControl.Contract;

type
  /// <summary>Was nach „Branch anlegen“ im Hauptthread folgt.</summary>
  TAtlasVcsBranchFinish = (
    /// <summary>Den Branch gibt es schon: melden, nichts angelegt.</summary>
    Exists,
    /// <summary>Den Ordner des worktree gibt es schon: melden, nichts angelegt.</summary>
    FolderTaken,
    /// <summary>Angelegt (auch wenn nur der Push scheiterte): melden, danach anbieten.</summary>
    Created,
    /// <summary>Abruf gescheitert: fragen, ob vom lokalen Stand abgezweigt wird.</summary>
    OfferLocal,
    /// <summary>Gescheitert: Schritt und Grund melden.</summary>
    Failed);

  TAtlasVcsPlan = record
  public
    /// <summary>Das größere aus AMinimumMs und ATimeoutMs.</summary>
    class function AtLeast(ATimeoutMs, AMinimumMs: Cardinal): Cardinal; static;
    /// <summary>Zustand ohne Prozess: AProvider aus, Arbeitskopie der Art ACopyKind, Umsetzung der Art AVcsKind
    /// (None ohne Programm).</summary>
    class function LocalOutcome(AProvider: TAtlasVcsProvider; ACopyKind, AVcsKind: TAtlasVcsKind): TAtlasVcsOutcome;
      static;
    /// <summary>Ort der Suche nach dem Branch: der Ort aus dem Dialog (ALocation, unter „^/“), sonst ADefault.
    /// </summary>
    class function SearchLocation(const ALocation, ADefault: string): string; static;
    /// <summary>Was nach dem Lauf folgt: AExists Branch da, ATaken Ordner da, ACreated angelegt (oder nur der Push
    /// scheiterte), AOfferLocal Rückfrage nach gescheitertem Abruf erlaubt, AFetchFailed der Abruf scheiterte.
    /// </summary>
    class function BranchFinish(AExists, ATaken, ACreated, AOfferLocal, AFetchFailed: Boolean): TAtlasVcsBranchFinish;
      static;
  end;

implementation

{ TAtlasVcsPlan }

class function TAtlasVcsPlan.AtLeast(ATimeoutMs, AMinimumMs: Cardinal): Cardinal;
begin
  Result := ATimeoutMs;
  if AMinimumMs > Result then
  begin
    Result := AMinimumMs;
  end;
end;

class function TAtlasVcsPlan.LocalOutcome(AProvider: TAtlasVcsProvider; ACopyKind,
  AVcsKind: TAtlasVcsKind): TAtlasVcsOutcome;
begin
  if AProvider = TAtlasVcsProvider.Off then
  begin
    Result := TAtlasVcsOutcome.Disabled;
  end
  else if ACopyKind = TAtlasVcsKind.None then
  begin
    Result := TAtlasVcsOutcome.NoWorkingCopy;
  end
  else if AVcsKind = TAtlasVcsKind.None then
  begin
    Result := TAtlasVcsOutcome.ToolMissing;
  end
  else
  begin
    Result := TAtlasVcsOutcome.Ok;
  end;
end;

class function TAtlasVcsPlan.SearchLocation(const ALocation, ADefault: string): string;
begin
  Result := ADefault;
  if ALocation <> '' then
  begin
    Result := '^/' + ALocation;
  end;
end;

class function TAtlasVcsPlan.BranchFinish(AExists, ATaken, ACreated, AOfferLocal,
  AFetchFailed: Boolean): TAtlasVcsBranchFinish;
begin
  if AExists then
  begin
    Result := TAtlasVcsBranchFinish.Exists;
  end
  else if ATaken then
  begin
    Result := TAtlasVcsBranchFinish.FolderTaken;
  end
  else if ACreated then
  begin
    Result := TAtlasVcsBranchFinish.Created;
  end
  else if AOfferLocal and AFetchFailed then
  begin
    Result := TAtlasVcsBranchFinish.OfferLocal;
  end
  else
  begin
    Result := TAtlasVcsBranchFinish.Failed;
  end;
end;

end.
