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
    /// <summary>Commits neueste zuerst (höchstens THotspotAnalyzer.HistoryLimit).</summary>
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
    HistoryLimit = 50;
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
    Exit;
  for mName in AAuthors do
    if SameText(mName, AAuthor) then
      Exit;
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
    Result := LowerCase(ChangeFileExt(StringReplace(APath, '\', '/', [rfReplaceAll]), ''))
  else
    Result := '';
end;

class function THotspotAnalyzer.IsSource(const APath: string): Boolean;
var
  mExtension: string;
begin
  mExtension := LowerCase(ExtractFileExt(APath));
  Result := (mExtension = '.pas') or (mExtension = '.dpr');
end;

class function THotspotAnalyzer.UnitChanges(const AUnits: TArray<THotspotUnit>;
  const ACommits: TArray<THotspotCommit>): TArray<THotspotChanges>;
var
  mByPath: TDictionary<string, Integer>;
  mIndex, mUnit: Integer;
  mCommit: THotspotCommit;
  mFile: THotspotFileChange;
  mSeen: TArray<Boolean>;
  mEntry: THotspotLineCommit;
  mAdded, mDeleted: Integer;
begin
  SetLength(Result, Length(AUnits));
  SetLength(mSeen, Length(AUnits));
  for mIndex := 0 to High(Result) do
    Result[mIndex] := Default(THotspotChanges);
  mByPath := TDictionary<string, Integer>.Create;
  try
    for mIndex := 0 to High(AUnits) do
      mByPath.AddOrSetValue(LowerCase(AUnits[mIndex].Path), mIndex);
    for mCommit in ACommits do
    begin
      for mIndex := 0 to High(mSeen) do
        mSeen[mIndex] := False;
      for mFile in mCommit.Files do
      begin
        if (mFile.Kind = THotspotChangeKind.Deleted) or not IsSource(mFile.Path) or
          not mByPath.TryGetValue(LowerCase(mFile.Path), mUnit) then
          Continue;
        mAdded := mFile.Added;
        mDeleted := mFile.Deleted;
        if mSeen[mUnit] then
          Continue;
        mSeen[mUnit] := True;
        Inc(Result[mUnit].Changes);
        Result[mUnit].Authors := AddAuthor(Result[mUnit].Authors, mCommit.Author);
        if Result[mUnit].Changes = 1 then
        begin
          Result[mUnit].Added := Max(mAdded, -1);
          Result[mUnit].Deleted := Max(mDeleted, -1);
        end
        else if (Result[mUnit].Added >= 0) and (mAdded >= 0) and (mDeleted >= 0) then
        begin
          Inc(Result[mUnit].Added, mAdded);
          Inc(Result[mUnit].Deleted, mDeleted);
        end
        else
        begin
          Result[mUnit].Added := -1;
          Result[mUnit].Deleted := -1;
        end;
        if mCommit.Date > Result[mUnit].LastChange then
          Result[mUnit].LastChange := mCommit.Date;
        if Length(Result[mUnit].History) < HistoryLimit then
        begin
          mEntry := Default(THotspotLineCommit);
          mEntry.Revision := mCommit.Revision;
          mEntry.Author := mCommit.Author;
          mEntry.Date := mCommit.Date;
          mEntry.Summary := mCommit.Summary;
          mEntry.Added := mAdded;
          mEntry.Deleted := mDeleted;
          Result[mUnit].History := Result[mUnit].History + [mEntry];
        end;
      end;
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
      Result.LastChange := mCommit.Date;
    if Length(Result.History) < HistoryLimit then
      Result.History := Result.History + [mCommit];
  end;
end;

function CompareEntries(const ALeft, ARight: THotspotEntry): Integer;
begin
  Result := CompareValue(ARight.Score, ALeft.Score);
  if Result = 0 then
    Result := ARight.Changes.Changes - ALeft.Changes.Changes;
  if Result = 0 then
    Result := ARight.Complexity - ALeft.Complexity;
  if Result = 0 then
    Result := CompareText(ALeft.Path, ARight.Path);
  if Result = 0 then
    Result := CompareStr(ALeft.Path, ARight.Path);
  if Result = 0 then
    Result := CompareText(ALeft.Method, ARight.Method);
  if Result = 0 then
    Result := ALeft.Line - ARight.Line;
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
    if mEntry.Changes.Changes > 0 then
    begin
      mMaxChanges := Max(mMaxChanges, mEntry.Changes.Changes);
      mMaxComplexity := Max(mMaxComplexity, mEntry.Complexity);
    end;
  mList := TList<THotspotEntry>.Create;
  try
    for mEntry in AEntries do
    begin
      if mEntry.Changes.Changes <= 0 then
        Continue;
      mScored := mEntry;
      if mMaxComplexity > 0 then
        mScored.Score := (mEntry.Changes.Changes / mMaxChanges) * (Max(0, mEntry.Complexity) / mMaxComplexity)
      else
        mScored.Score := 0;
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
    Exit(THotspotTrend.New);
  if APast < 0 then
    Exit(THotspotTrend.Unknown);
  mTolerance := Max(1, Round(APast * 0.05));
  if ANow - APast > mTolerance then
    Result := THotspotTrend.Rising
  else if APast - ANow > mTolerance then
    Result := THotspotTrend.Falling
  else
    Result := THotspotTrend.Steady;
end;

function CompareCoupling(const ALeft, ARight: THotspotCoupling): Integer;
begin
  Result := CompareValue(ARight.Ratio, ALeft.Ratio);
  if Result = 0 then
    Result := ARight.Shared - ALeft.Shared;
  if Result = 0 then
    Result := CompareText(ALeft.First.Path, ARight.First.Path);
  if Result = 0 then
    Result := CompareText(ALeft.Second.Path, ARight.Second.Path);
  if Result = 0 then
    Result := CompareStr(ALeft.First.Path + #1 + ALeft.Second.Path, ARight.First.Path + #1 + ARight.Second.Path);
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
  mFile: THotspotFileChange;
  mIndex, mInner, mUnit, mFirst, mSecond, mShared: Integer;
  mKey: string;
  mPair: TPair<Int64, Integer>;
  mItem: THotspotCoupling;
  mList: TList<THotspotCoupling>;
  mRatio: Double;
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
    for mIndex := 0 to High(AUnits) do
    begin
      mKey := UnitKey(AUnits[mIndex].Path);
      if mKey <> '' then
        mByKey.AddOrSetValue(mKey, mIndex);
    end;
    for mCommit in ACommits do
    begin
      if Length(mCommit.Files) > AOptions.MaxCommitFiles then
        Continue;
      mTouched.Clear;
      for mFile in mCommit.Files do
      begin
        if mFile.Kind = THotspotChangeKind.Deleted then
          Continue;
        mKey := UnitKey(mFile.Path);
        if (mKey = '') or not mByKey.TryGetValue(mKey, mUnit) or mSeen[mUnit] then
          Continue;
        mSeen[mUnit] := True;
        mTouched.Add(mUnit);
      end;
      mTouched.Sort;
      for mIndex := 0 to mTouched.Count - 1 do
      begin
        mSeen[mTouched[mIndex]] := False;
        Inc(mCounts[mTouched[mIndex]]);
        for mInner := mIndex + 1 to mTouched.Count - 1 do
        begin
          mFirst := mTouched[mIndex];
          mSecond := mTouched[mInner];
          if mPairs.TryGetValue(mFirst * mUnitCount + mSecond, mShared) then
            mPairs[mFirst * mUnitCount + mSecond] := mShared + 1
          else
            mPairs.Add(mFirst * mUnitCount + mSecond, 1);
        end;
      end;
    end;
    for mPair in mPairs do
    begin
      if mPair.Value < AOptions.MinSharedCommits then
        Continue;
      mFirst := Integer(mPair.Key div mUnitCount);
      mSecond := Integer(mPair.Key mod mUnitCount);
      mRatio := mPair.Value / ((mCounts[mFirst] + mCounts[mSecond]) / 2);
      if mRatio + 1E-9 < AOptions.MinCouplingRatio then
        Continue;
      if Assigned(AConnected) and AConnected(mFirst, mSecond) then
        Continue;
      mItem.First := AUnits[mFirst];
      mItem.Second := AUnits[mSecond];
      mItem.Shared := mPair.Value;
      mItem.FirstChanges := mCounts[mFirst];
      mItem.SecondChanges := mCounts[mSecond];
      mItem.Ratio := mRatio;
      mList.Add(mItem);
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
