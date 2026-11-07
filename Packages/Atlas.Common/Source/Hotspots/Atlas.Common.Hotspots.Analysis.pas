unit Atlas.Common.Hotspots.Analysis;

// Rechnung der Hotspots (#1354), ohne Versionsverwaltung und ohne Dateien:
//
// - Änderungen je Unit: Commits, die eine ihrer Quelldateien (.pas, .dpr)
//   ändern, Autoren, geänderte Zeilen (-1, sobald ein Commit keine Zahl
//   kennt, z. B. SVN), letzte Änderung.
// - Wert = Änderungen / größte Änderungszahl × Komplexität / größte
//   Komplexität, beides über die Kandidaten derselben Ebene; liegt also
//   zwischen 0 und 1. Komplexität = kognitive Komplexität (Summe über die
//   Routinen einer Unit bzw. die der Methode).
// - Trend: Komplexität heute gegen damals; mehr als 5 % (mindestens 1)
//   Unterschied ist steigend bzw. fallend.
// - Änderungskopplung: Paare von Units, die in mindestens AMinShared Commits
//   gemeinsam geändert wurden, Anteil = gemeinsame / Mittel der Commits
//   beider ≥ AMinRatio, ohne uses-Kante in eine der beiden Richtungen.
//   .pas, .dfm und .fmx derselben Unit zählen als eine Unit (keine Paare
//   untereinander); Commits mit mehr als AMaxFiles Dateien zählen nicht.
// - Reihenfolge eindeutig: Wert, Änderungen, Komplexität absteigend, dann
//   Pfad, Methode und Zeile aufsteigend.

interface

uses
  System.SysUtils,
  Atlas.Common.Hotspots.Contract;

type
  /// <summary>Unit im Umfang: Pfad relativ zur Wurzel der Arbeitskopie mit "/".</summary>
  THotspotUnit = record
    UnitName: string;
    FileName: string;
    Path: string;
  end;

  /// <summary>Änderungen einer Unit bzw. Methode im Zeitraum.</summary>
  THotspotChanges = record
    Changes: Integer;
    Authors: TArray<string>;
    /// <summary>-1 unbekannt.</summary>
    Added: Integer;
    Deleted: Integer;
    LastChange: TDateTime;
    /// <summary>Commits neueste zuerst (höchstens THotspotAnalyzer.cHistoryLimit).</summary>
    History: TArray<THotspotLineCommit>;
  end;

  /// <summary>Eine Zeile der Rangliste (Unit oder Methode).</summary>
  THotspotEntry = record
    UnitName: string;
    Path: string;
    FileName: string;
    /// <summary>Methode wie im Kopf (TFoo.Bar); '' auf Unit-Ebene.</summary>
    Method: string;
    /// <summary>1-basiert; Units 1.</summary>
    Line: Integer;
    EndLine: Integer;
    Changes: THotspotChanges;
    Complexity: Integer;
    /// <summary>Zeilen der Unit bzw. Methode.</summary>
    Lines: Integer;
    /// <summary>Komplexität vor THotspotOptions.TrendMonths Monaten; -1 unbekannt.</summary>
    PastComplexity: Integer;
    Trend: THotspotTrend;
    Score: Double;
  end;

  THotspotCoupling = record
    First: THotspotUnit;
    Second: THotspotUnit;
    Shared: Integer;
    FirstChanges: Integer;
    SecondChanges: Integer;
    /// <summary>Gemeinsame Commits / Mittel der Commits beider (0–1).</summary>
    Ratio: Double;
  end;

  /// <summary>Ergebnis einer Auswertung für Bericht, Fenster und get_hotspots.</summary>
  THotspotResult = record
    Title: string;
    /// <summary>Wurzel der Arbeitskopie; Pfade der Einträge sind relativ dazu.</summary>
    Root: string;
    Kind: THotspotVcsKind;
    Head: string;
    Months: Integer;
    /// <summary>Beginn des Zeitraums (UTC).</summary>
    Since: TDateTime;
    /// <summary>Ausgewertete Commits im Zeitraum.</summary>
    Commits: Integer;
    Level: THotspotLevel;
    Units: TArray<THotspotEntry>;
    /// <summary>Nur auf Methodenebene gefüllt.</summary>
    Methods: TArray<THotspotEntry>;
    Coupling: TArray<THotspotCoupling>;
    /// <summary>Index-Generation der Komplexität.</summary>
    Generation: Int64;
  end;

  /// <summary>Gibt es eine uses-Kante zwischen den Units AFirst und ASecond (Index in der Unit-Liste) in einer
  /// der beiden Richtungen?</summary>
  THotspotConnectedFunc = reference to function(AFirst, ASecond: Integer): Boolean;

  THotspotAnalyzer = record
  public const
    cHistoryLimit = 50;
  public
    /// <summary>Änderungen je Unit (Reihenfolge wie AUnits). ACommits mit heutigen Pfaden (FollowRenames).</summary>
    class function UnitChanges(const AUnits: TArray<THotspotUnit>;
      const ACommits: TArray<THotspotCommit>): TArray<THotspotChanges>; static;
    /// <summary>Änderungen aus den Commits eines Zeilenbereichs (Methode).</summary>
    class function LineChanges(const ACommits: TArray<THotspotLineCommit>): THotspotChanges; static;
    /// <summary>Setzt Score aller Einträge (normiert über AEntries) und sortiert eindeutig; Einträge ohne Änderung
    /// fallen weg.</summary>
    class function Rank(const AEntries: TArray<THotspotEntry>): TArray<THotspotEntry>; static;
    /// <summary>Trend aus heute und damals (APast -1 = unbekannt, -2 = gab es noch nicht).</summary>
    class function TrendOf(ANow, APast: Integer): THotspotTrend; static;
    /// <summary>Änderungskopplung der Units AUnits; AConnected sagt, ob eine uses-Kante sie verbindet.</summary>
    class function Coupling(const AUnits: TArray<THotspotUnit>; const ACommits: TArray<THotspotCommit>;
      const AOptions: THotspotOptions; const AConnected: THotspotConnectedFunc): TArray<THotspotCoupling>; static;
    /// <summary>Schlüssel einer Datei zu ihrer Unit: Pfad ohne Endung in Kleinschreibung für .pas, .dpr, .dfm,
    /// .fmx, .lfm; '' für andere Dateien.</summary>
    class function UnitKey(const APath: string): string; static;
    /// <summary>Quelldatei einer Unit (.pas, .dpr), deren Änderung als Änderung der Unit zählt.</summary>
    class function IsSource(const APath: string): Boolean; static;
  end;

implementation

uses
  System.Math,
  System.Generics.Collections,
  System.Generics.Defaults;

function AddAuthor(const AAuthors: TArray<string>; const AAuthor: string): TArray<string>;
var
  mName: string;
begin
  Result := AAuthors;
  if AAuthor = '' then
  begin
    Exit;
  end;
  for mName in AAuthors do
  begin
    if SameText(mName, AAuthor) then
    begin
      Exit;
    end;
  end;
  Result := AAuthors + [AAuthor];
end;

{ THotspotAnalyzer }

class function THotspotAnalyzer.UnitKey(const APath: string): string;
var
  mExtension: string;
begin
  mExtension := LowerCase(ExtractFileExt(APath));
  if (mExtension = '.pas') or (mExtension = '.dpr') or (mExtension = '.dfm') or (mExtension = '.fmx') or
    (mExtension = '.lfm') then
  begin
    Result := LowerCase(ChangeFileExt(StringReplace(APath, '\', '/', [rfReplaceAll]), ''));
  end
  else
  begin
    Result := '';
  end;
end;

class function THotspotAnalyzer.IsSource(const APath: string): Boolean;
var
  mExtension: string;
begin
  mExtension := LowerCase(ExtractFileExt(APath));
  Result := (mExtension = '.pas') or (mExtension = '.dpr');
end;

/// <summary>Zählt Zeilen einer weiteren Änderung zu AChanges; -1, sobald eine Änderung sie nicht kennt.</summary>
procedure AddLines(var AChanges: THotspotChanges; AAdded, ADeleted: Integer);
begin
  if AChanges.Changes = 1 then
  begin
    AChanges.Added := Max(AAdded, -1);
    AChanges.Deleted := Max(ADeleted, -1);
  end
  else if (AChanges.Added >= 0) and (AAdded >= 0) and (ADeleted >= 0) then
  begin
    Inc(AChanges.Added, AAdded);
    Inc(AChanges.Deleted, ADeleted);
  end
  else
  begin
    AChanges.Added := -1;
    AChanges.Deleted := -1;
  end;
end;

function HistoryEntry(const ACommit: THotspotCommit; const AFile: THotspotFileChange): THotspotLineCommit;
begin
  Result := Default(THotspotLineCommit);
  Result.Revision := ACommit.Revision;
  Result.Author := ACommit.Author;
  Result.Date := ACommit.Date;
  Result.Summary := ACommit.Summary;
  Result.Added := AFile.Added;
  Result.Deleted := AFile.Deleted;
end;

/// <summary>Zählt die Änderung AFile aus ACommit in AChanges ein.</summary>
procedure CountChange(var AChanges: THotspotChanges; const ACommit: THotspotCommit; const AFile: THotspotFileChange);
begin
  Inc(AChanges.Changes);
  AChanges.Authors := AddAuthor(AChanges.Authors, ACommit.Author);
  AddLines(AChanges, AFile.Added, AFile.Deleted);
  if ACommit.Date > AChanges.LastChange then
  begin
    AChanges.LastChange := ACommit.Date;
  end;
  if Length(AChanges.History) < THotspotAnalyzer.cHistoryLimit then
  begin
    AChanges.History := AChanges.History + [HistoryEntry(ACommit, AFile)];
  end;
end;

/// <summary>Zählt ACommit bei jeder Unit aus AByPath höchstens einmal.</summary>
procedure CountCommit(var AChanges: TArray<THotspotChanges>; AByPath: TDictionary<string, Integer>;
  const ACommit: THotspotCommit);
var
  mSeen: TArray<Boolean>;
  mFile: THotspotFileChange;
  mUnit: Integer;
begin
  SetLength(mSeen, Length(AChanges));
  for mFile in ACommit.Files do
  begin
    if (mFile.Kind <> THotspotChangeKind.Deleted) and THotspotAnalyzer.IsSource(mFile.Path) and
      AByPath.TryGetValue(LowerCase(mFile.Path), mUnit) and not mSeen[mUnit] then
    begin
      mSeen[mUnit] := True;
      CountChange(AChanges[mUnit], ACommit, mFile);
    end;
  end;
end;

class function THotspotAnalyzer.UnitChanges(const AUnits: TArray<THotspotUnit>;
  const ACommits: TArray<THotspotCommit>): TArray<THotspotChanges>;
var
  mByPath: TDictionary<string, Integer>;
  mIndex: Integer;
  mCommit: THotspotCommit;
begin
  SetLength(Result, Length(AUnits));
  for mIndex := 0 to High(Result) do
  begin
    Result[mIndex] := Default(THotspotChanges);
  end;
  mByPath := TDictionary<string, Integer>.Create;
  try
    for mIndex := 0 to High(AUnits) do
    begin
      mByPath.AddOrSetValue(LowerCase(AUnits[mIndex].Path), mIndex);
    end;
    for mCommit in ACommits do
    begin
      CountCommit(Result, mByPath, mCommit);
    end;
  finally
    mByPath.Free;
  end;
end;

class function THotspotAnalyzer.LineChanges(const ACommits: TArray<THotspotLineCommit>): THotspotChanges;
var
  mCommit: THotspotLineCommit;
begin
  Result := Default(THotspotChanges);
  for mCommit in ACommits do
  begin
    Inc(Result.Changes);
    Result.Authors := AddAuthor(Result.Authors, mCommit.Author);
    if Result.Changes = 1 then
    begin
      Result.Added := Max(mCommit.Added, -1);
      Result.Deleted := Max(mCommit.Deleted, -1);
    end
    else if (Result.Added >= 0) and (mCommit.Added >= 0) and (mCommit.Deleted >= 0) then
    begin
      Inc(Result.Added, mCommit.Added);
      Inc(Result.Deleted, mCommit.Deleted);
    end
    else
    begin
      Result.Added := -1;
      Result.Deleted := -1;
    end;
    if mCommit.Date > Result.LastChange then
    begin
      Result.LastChange := mCommit.Date;
    end;
    if Length(Result.History) < cHistoryLimit then
    begin
      Result.History := Result.History + [mCommit];
    end;
  end;
end;

function CompareEntries(const ALeft, ARight: THotspotEntry): Integer;
begin
  Result := CompareValue(ARight.Score, ALeft.Score);
  if Result = 0 then
  begin
    Result := ARight.Changes.Changes - ALeft.Changes.Changes;
  end;
  if Result = 0 then
  begin
    Result := ARight.Complexity - ALeft.Complexity;
  end;
  if Result = 0 then
  begin
    Result := CompareText(ALeft.Path, ARight.Path);
  end;
  if Result = 0 then
  begin
    Result := CompareStr(ALeft.Path, ARight.Path);
  end;
  if Result = 0 then
  begin
    Result := CompareText(ALeft.Method, ARight.Method);
  end;
  if Result = 0 then
  begin
    Result := ALeft.Line - ARight.Line;
  end;
end;

class function THotspotAnalyzer.Rank(const AEntries: TArray<THotspotEntry>): TArray<THotspotEntry>;
var
  mList: TList<THotspotEntry>;
  mEntry, mScored: THotspotEntry;
  mMaxChanges, mMaxComplexity: Integer;
begin
  mMaxChanges := 0;
  mMaxComplexity := 0;
  for mEntry in AEntries do
  begin
    if mEntry.Changes.Changes > 0 then
    begin
      mMaxChanges := Max(mMaxChanges, mEntry.Changes.Changes);
      mMaxComplexity := Max(mMaxComplexity, mEntry.Complexity);
    end;
  end;
  mList := TList<THotspotEntry>.Create;
  try
    for mEntry in AEntries do
    begin
      if mEntry.Changes.Changes <= 0 then
      begin
        Continue;
      end;
      mScored := mEntry;
      if mMaxComplexity > 0 then
      begin
        mScored.Score := (mEntry.Changes.Changes / mMaxChanges) * (Max(0, mEntry.Complexity) / mMaxComplexity);
      end
      else
      begin
        mScored.Score := 0;
      end;
      mList.Add(mScored);
    end;
    // TList.Sort ist nicht stabil: CompareEntries entscheidet bis zur Zeile eindeutig.
    mList.Sort(TComparer<THotspotEntry>.Construct(CompareEntries));
    Result := mList.ToArray;
  finally
    mList.Free;
  end;
end;

class function THotspotAnalyzer.TrendOf(ANow, APast: Integer): THotspotTrend;
var
  mTolerance: Integer;
begin
  if APast = -2 then
  begin
    Exit(THotspotTrend.New);
  end;
  if APast < 0 then
  begin
    Exit(THotspotTrend.Unknown);
  end;
  mTolerance := Max(1, Round(APast * 0.05));
  if ANow - APast > mTolerance then
  begin
    Result := THotspotTrend.Rising;
  end
  else if APast - ANow > mTolerance then
  begin
    Result := THotspotTrend.Falling;
  end
  else
  begin
    Result := THotspotTrend.Steady;
  end;
end;

function CompareCoupling(const ALeft, ARight: THotspotCoupling): Integer;
begin
  Result := CompareValue(ARight.Ratio, ALeft.Ratio);
  if Result = 0 then
  begin
    Result := ARight.Shared - ALeft.Shared;
  end;
  if Result = 0 then
  begin
    Result := CompareText(ALeft.First.Path, ARight.First.Path);
  end;
  if Result = 0 then
  begin
    Result := CompareText(ALeft.Second.Path, ARight.Second.Path);
  end;
  if Result = 0 then
  begin
    Result := CompareStr(ALeft.First.Path + #1 + ALeft.Second.Path, ARight.First.Path + #1 + ARight.Second.Path);
  end;
end;

/// <summary>Units, die ACommit ändert, je einmal und aufsteigend; ASeen ist danach wieder ganz False.</summary>
procedure CollectTouched(const ACommit: THotspotCommit; AByKey: TDictionary<string, Integer>;
  var ASeen: TArray<Boolean>; ATouched: TList<Integer>);
var
  mFile: THotspotFileChange;
  mKey: string;
  mUnit: Integer;
begin
  ATouched.Clear;
  for mFile in ACommit.Files do
  begin
    mKey := '';
    if mFile.Kind <> THotspotChangeKind.Deleted then
    begin
      mKey := THotspotAnalyzer.UnitKey(mFile.Path);
    end;
    if (mKey <> '') and AByKey.TryGetValue(mKey, mUnit) and not ASeen[mUnit] then
    begin
      ASeen[mUnit] := True;
      ATouched.Add(mUnit);
    end;
  end;
  ATouched.Sort;
  for mUnit in ATouched do
  begin
    ASeen[mUnit] := False;
  end;
end;

/// <summary>Zählt die Commits je Unit (ACounts) und je Paar (APairs, Schlüssel Erste * AUnitCount + Zweite).
/// </summary>
procedure CountPairs(ATouched: TList<Integer>; var ACounts: TArray<Integer>; APairs: TDictionary<Int64, Integer>;
  AUnitCount: Int64);
var
  mIndex, mInner, mShared: Integer;
  mKey: Int64;
begin
  for mIndex := 0 to ATouched.Count - 1 do
  begin
    Inc(ACounts[ATouched[mIndex]]);
    for mInner := mIndex + 1 to ATouched.Count - 1 do
    begin
      mKey := ATouched[mIndex] * AUnitCount + ATouched[mInner];
      if not APairs.TryGetValue(mKey, mShared) then
      begin
        mShared := 0;
      end;
      APairs.AddOrSetValue(mKey, mShared + 1);
    end;
  end;
end;

/// <summary>Schlüssel der Units (UnitKey) auf ihren Index in AUnits.</summary>
procedure FillUnitKeys(AByKey: TDictionary<string, Integer>; const AUnits: TArray<THotspotUnit>);
var
  mIndex: Integer;
  mKey: string;
begin
  for mIndex := 0 to High(AUnits) do
  begin
    mKey := THotspotAnalyzer.UnitKey(AUnits[mIndex].Path);
    if mKey <> '' then
    begin
      AByKey.AddOrSetValue(mKey, mIndex);
    end;
  end;
end;

/// <summary>Kopplung des Paars APair (Schlüssel wie CountPairs, Wert gemeinsame Commits); False unter den
/// Schwellen oder mit uses-Kante.</summary>
function TryCoupling(const AUnits: TArray<THotspotUnit>; const ACounts: TArray<Integer>;
  const APair: TPair<Int64, Integer>; const AOptions: THotspotOptions; const AConnected: THotspotConnectedFunc;
  out AItem: THotspotCoupling): Boolean;
var
  mRatio: Double;
  mFirst, mSecond, mShared: Integer;
begin
  AItem := Default(THotspotCoupling);
  mFirst := Integer(APair.Key div Length(AUnits));
  mSecond := Integer(APair.Key mod Length(AUnits));
  mShared := APair.Value;
  mRatio := mShared / ((ACounts[mFirst] + ACounts[mSecond]) / 2);
  Result := (mShared >= AOptions.MinSharedCommits) and (mRatio + 1E-9 >= AOptions.MinCouplingRatio);
  if Result and Assigned(AConnected) then
  begin
    Result := not AConnected(mFirst, mSecond);
  end;
  if Result then
  begin
    AItem.First := AUnits[mFirst];
    AItem.Second := AUnits[mSecond];
    AItem.Shared := mShared;
    AItem.FirstChanges := ACounts[mFirst];
    AItem.SecondChanges := ACounts[mSecond];
    AItem.Ratio := mRatio;
  end;
end;

class function THotspotAnalyzer.Coupling(const AUnits: TArray<THotspotUnit>; const ACommits: TArray<THotspotCommit>;
  const AOptions: THotspotOptions; const AConnected: THotspotConnectedFunc): TArray<THotspotCoupling>;
var
  mByKey: TDictionary<string, Integer>;
  mPairs: TDictionary<Int64, Integer>;
  mCounts: TArray<Integer>;
  mTouched: TList<Integer>;
  mSeen: TArray<Boolean>;
  mCommit: THotspotCommit;
  mPair: TPair<Int64, Integer>;
  mItem: THotspotCoupling;
  mList: TList<THotspotCoupling>;
  mUnitCount: Int64;
begin
  mUnitCount := Length(AUnits);
  SetLength(mCounts, Length(AUnits));
  SetLength(mSeen, Length(AUnits));
  mByKey := TDictionary<string, Integer>.Create;
  mPairs := TDictionary<Int64, Integer>.Create;
  mTouched := TList<Integer>.Create;
  mList := TList<THotspotCoupling>.Create;
  try
    FillUnitKeys(mByKey, AUnits);
    for mCommit in ACommits do
    begin
      if Length(mCommit.Files) <= AOptions.MaxCommitFiles then
      begin
        CollectTouched(mCommit, mByKey, mSeen, mTouched);
        CountPairs(mTouched, mCounts, mPairs, mUnitCount);
      end;
    end;
    for mPair in mPairs do
    begin
      if TryCoupling(AUnits, mCounts, mPair, AOptions, AConnected, mItem) then
      begin
        mList.Add(mItem);
      end;
    end;
    mList.Sort(TComparer<THotspotCoupling>.Construct(CompareCoupling));
    Result := mList.ToArray;
  finally
    mList.Free;
    mTouched.Free;
    mPairs.Free;
    mByKey.Free;
  end;
end;

end.
