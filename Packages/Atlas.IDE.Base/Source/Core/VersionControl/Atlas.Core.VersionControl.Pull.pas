unit Atlas.Core.VersionControl.Pull;

// Arbeitskopie vorwärts holen, ohne VCL und IDE (#764, aus den Schnellaktionen
// der Willkommensseite nach Base gezogen, #1456): Pull prüft vor dem Holen die
// ganze Arbeitskopie (geänderte versionierte Dateien sperren, unversionierte
// nicht) und holt dann nur vorwärts (Git: pull --ff-only, SVN: update;
// IAtlasVcsUpdate). AIgnoreExternals holt unter SVN ohne Externals
// (svn update --ignore-externals, #1292). Knopf „Pull“ der Willkommensseite
// und Fenster „Arbeitskopien“ holen beide hierüber.

interface

uses
  Atlas.Core.VersionControl.Contract;

type
{$SCOPEDENUMS ON}
  /// <summary>Ergebnis von Pull: neue Commits geholt, schon aktuell, wegen lokaler Änderungen nicht geholt, keine
  /// Arbeitskopie, Fehler (auch Zeitüberschreitung oder fehlendes Programm).</summary>
  TAtlasPullOutcome = (Updated, UpToDate, Blocked, NoWorkingCopy, Failed);
{$SCOPEDENUMS OFF}

  /// <summary>Holen einer Arbeitskopie über IAtlasVersionControl.</summary>
  TAtlasVcsPull = class
  public
    /// <summary>Sperren die Änderungen der Arbeitskopie Pull? Ja bei jeder Änderung außer unversionierten Dateien.
    /// </summary>
    class function ChangesBlockPull(const AChanges: TArray<TAtlasVcsChange>): Boolean; static;
    /// <summary>Pull bzw. svn update (startet Prozesse: nur im Hintergrund).</summary>
    class function Pull(const AVcs: IAtlasVersionControl): TAtlasPullOutcome; overload; static;
    /// <summary>Wie oben; AReason ist das Ergebnis des gescheiterten Aufrufs (für die Meldung bei Failed), sonst
    /// Ok.</summary>
    class function Pull(const AVcs: IAtlasVersionControl; out AReason: TAtlasVcsOutcome): TAtlasPullOutcome;
      overload; static;
    /// <summary>Wie oben; AIgnoreExternals: SVN ohne Externals (svn update --ignore-externals, #1292), sonst wie
    /// Pull. Git kennt das nicht und holt wie immer.</summary>
    class function Pull(const AVcs: IAtlasVersionControl; AIgnoreExternals: Boolean;
      out AReason: TAtlasVcsOutcome): TAtlasPullOutcome; overload; static;
  end;

implementation

uses
  System.SysUtils;

class function TAtlasVcsPull.ChangesBlockPull(const AChanges: TArray<TAtlasVcsChange>): Boolean;
var
  mChange: TAtlasVcsChange;
begin
  Result := False;
  for mChange in AChanges do
  begin
    if mChange.Kind <> TAtlasVcsChangeKind.Untracked then
    begin
      Exit(True);
    end;
  end;
end;

class function TAtlasVcsPull.Pull(const AVcs: IAtlasVersionControl): TAtlasPullOutcome;
var
  mReason: TAtlasVcsOutcome;
begin
  Result := Pull(AVcs, mReason);
end;

class function TAtlasVcsPull.Pull(const AVcs: IAtlasVersionControl;
  out AReason: TAtlasVcsOutcome): TAtlasPullOutcome;
begin
  Result := Pull(AVcs, False, AReason);
end;

/// <summary>Vor dem Holen frisch prüfen (der gezeigte Stand kann älter sein): Kopf in ABefore, Ergebnis Pull bei
/// UpToDate, sonst das Hindernis; AReason ist das Ergebnis des gescheiterten Aufrufs.</summary>
function CheckBefore(const AVcs: IAtlasVersionControl; out ABefore: TAtlasVcsHead;
  out AReason: TAtlasVcsOutcome): TAtlasPullOutcome;
var
  mChanges: TArray<TAtlasVcsChange>;
begin
  Result := TAtlasPullOutcome.Failed;
  AReason := AVcs.Head(ABefore);
  if (AReason = TAtlasVcsOutcome.NoWorkingCopy) or (AReason = TAtlasVcsOutcome.Disabled) then
  begin
    AReason := TAtlasVcsOutcome.Ok;
    Result := TAtlasPullOutcome.NoWorkingCopy;
  end
  else if AReason = TAtlasVcsOutcome.Ok then
  begin
    AReason := AVcs.Changes(mChanges);
    if AReason <> TAtlasVcsOutcome.Ok then
    begin
      Result := TAtlasPullOutcome.Failed;
    end
    else if TAtlasVcsPull.ChangesBlockPull(mChanges) then
    begin
      Result := TAtlasPullOutcome.Blocked;
    end
    else
    begin
      Result := TAtlasPullOutcome.UpToDate;
    end;
  end;
end;

/// <summary>Holen selbst: unter SVN auf Wunsch ohne Externals, sonst IAtlasVcsUpdate; Failed ohne beides.</summary>
function Fetch(const AVcs: IAtlasVersionControl; AIgnoreExternals: Boolean): TAtlasVcsOutcome;
var
  mUpdate: IAtlasVcsUpdate;
  mExternals: IAtlasVcsSvnExternals;
begin
  if AIgnoreExternals and Supports(AVcs, IAtlasVcsSvnExternals, mExternals) then
  begin
    Result := mExternals.Update(True);
  end
  else if Supports(AVcs, IAtlasVcsUpdate, mUpdate) then
  begin
    Result := mUpdate.Pull;
  end
  else
  begin
    Result := TAtlasVcsOutcome.Failed;
  end;
end;

class function TAtlasVcsPull.Pull(const AVcs: IAtlasVersionControl; AIgnoreExternals: Boolean;
  out AReason: TAtlasVcsOutcome): TAtlasPullOutcome;
var
  mBefore, mAfter: TAtlasVcsHead;
begin
  AReason := TAtlasVcsOutcome.Ok;
  if AVcs = nil then
  begin
    Exit(TAtlasPullOutcome.NoWorkingCopy);
  end;
  Result := CheckBefore(AVcs, mBefore, AReason);
  if Result <> TAtlasPullOutcome.UpToDate then
  begin
    Exit;
  end;
  AReason := Fetch(AVcs, AIgnoreExternals);
  if AReason <> TAtlasVcsOutcome.Ok then
  begin
    Result := TAtlasPullOutcome.Failed;
  end
  else if (AVcs.Head(mAfter) = TAtlasVcsOutcome.Ok) and (mAfter.Revision <> mBefore.Revision) then
  begin
    Result := TAtlasPullOutcome.Updated;
  end;
end;

end.
