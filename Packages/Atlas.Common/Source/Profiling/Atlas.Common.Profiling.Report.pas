unit Atlas.Common.Profiling.Report;

// Stichproben-Profiler (#2057), Fachlogik: Auswertung eines Laufs (Atlas.Common.Profiling.Profile).
// - Methoden nach Eigenanteil (innerster Rahmen) und Gesamtanteil (irgendwo im Stapel, je Probe einmal), dazu die
//   heißeste Zeile jeder Methode (die Zeile, an der sie in den meisten Proben stand).
// - „Nur eigener Code“: Folgen von Bibliotheksrahmen (RTL, VCL …) zählen als ihr äußerster Rahmen, also die
//   Bibliotheksroutine, die der eigene Code aufgerufen hat. Ihr Anteil bleibt so sichtbar, ohne die Innereien.
// - Zeilen je Datei für das Wärmeband im Editor.
// - Vergleich zweier Läufe nach Anteilen, größte Änderung zuerst.
// Anteile sind auf die Proben bezogen, in denen gerechnet wurde.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Profiling.Profile;

type
  TAtlasProfileMethod = record
    Routine: string;
    UnitName: string;
    FileName: string;
    IsLibrary: Boolean;
    SelfCount: Integer;
    TotalCount: Integer;
    /// <summary>Zeile mit den meisten Proben dieser Methode; 0 = unbekannt.</summary>
    HotLine: Integer;
    HotLineCount: Integer;
  end;

  TAtlasProfileLine = record
    FileName: string;
    Line: Integer;
    Count: Integer;
  end;

  TAtlasProfileDelta = record
    Routine: string;
    IsLibrary: Boolean;
    SelfBefore: Double;
    SelfAfter: Double;
    TotalBefore: Double;
    TotalAfter: Double;
    function SelfChange: Double;
  end;

  TAtlasProfileAnalysis = record
  public
    /// <summary>Anteil in Prozent; 0 ohne Proben.</summary>
    class function Percent(ACount, ASamples: Integer): Double; static;
    /// <summary>Rahmen eines Stapels, mit AOwnOnly zusammengefasst (siehe oben); Index 0 = innerster.</summary>
    class function EffectiveFrames(const AProfile: TAtlasProfile; const AStack: TAtlasProfileStack;
      AOwnOnly: Boolean): TArray<Integer>; static;
    /// <summary>Alle Methoden, nach Eigenanteil, dann Gesamtanteil, dann Name.</summary>
    class function Methods(const AProfile: TAtlasProfile; AOwnOnly: Boolean): TArray<TAtlasProfileMethod>; static;
    /// <summary>Proben je Datei und Zeile (je Probe und Zeile einmal), nach Datei und Zeile.</summary>
    class function Lines(const AProfile: TAtlasProfile; AOwnOnly: Boolean): TArray<TAtlasProfileLine>; static;
    /// <summary>Methoden beider Läufe, nach Betrag der Änderung des Eigenanteils, dann Name.</summary>
    class function Compare(const ABefore, AAfter: TAtlasProfile; AOwnOnly: Boolean): TArray<TAtlasProfileDelta>;
      static;
  end;

implementation

uses
  System.Math,
  System.Generics.Defaults;

type
  /// <summary>Zwischenstand je Methode beim Zählen: Proben je Zeile.</summary>
  TMethodTally = class
  public
    Method: TAtlasProfileMethod;
    LineCounts: TDictionary<Integer, Integer>;
    constructor Create(const AFrame: TAtlasProfileFrame);
    destructor Destroy; override;
    procedure CountLine(ALine, ACount: Integer);
    procedure PickHotLine;
  end;

constructor TMethodTally.Create(const AFrame: TAtlasProfileFrame);
begin
  inherited Create;
  Method := Default(TAtlasProfileMethod);
  Method.Routine := AFrame.Routine;
  Method.UnitName := AFrame.UnitName;
  Method.FileName := AFrame.FileName;
  Method.IsLibrary := AFrame.IsLibrary;
  LineCounts := TDictionary<Integer, Integer>.Create;
end;

destructor TMethodTally.Destroy;
begin
  LineCounts.Free;
  inherited;
end;

procedure TMethodTally.CountLine(ALine, ACount: Integer);
var
  mCount: Integer;
begin
  if ALine <= 0 then
  begin
    Exit;
  end;
  if not LineCounts.TryGetValue(ALine, mCount) then
  begin
    mCount := 0;
  end;
  LineCounts.AddOrSetValue(ALine, mCount + ACount);
end;

procedure TMethodTally.PickHotLine;
var
  mPair: TPair<Integer, Integer>;
begin
  for mPair in LineCounts do
  begin
    // Bei Gleichstand die kleinere Zeile, damit das Ergebnis nicht von der Reihenfolge abhängt.
    if (mPair.Value > Method.HotLineCount) or
      ((mPair.Value = Method.HotLineCount) and (mPair.Key < Method.HotLine)) then
    begin
      Method.HotLine := mPair.Key;
      Method.HotLineCount := mPair.Value;
    end;
  end;
end;

{ TAtlasProfileDelta }

function TAtlasProfileDelta.SelfChange: Double;
begin
  Result := SelfAfter - SelfBefore;
end;

{ TAtlasProfileAnalysis }

class function TAtlasProfileAnalysis.Percent(ACount, ASamples: Integer): Double;
begin
  Result := 0;
  if ASamples > 0 then
  begin
    Result := 100 * ACount / ASamples;
  end;
end;

class function TAtlasProfileAnalysis.EffectiveFrames(const AProfile: TAtlasProfile;
  const AStack: TAtlasProfileStack; AOwnOnly: Boolean): TArray<Integer>;
var
  mPosition: Integer;
begin
  if not AOwnOnly then
  begin
    Exit(AStack.Frames);
  end;
  Result := nil;
  for mPosition := 0 to High(AStack.Frames) do
  begin
    // Ein Bibliotheksrahmen, dessen Aufrufer auch Bibliothek ist, geht im Aufrufer auf.
    if (mPosition < High(AStack.Frames)) and AProfile.Frames[AStack.Frames[mPosition]].IsLibrary and
      AProfile.Frames[AStack.Frames[mPosition + 1]].IsLibrary then
    begin
      Continue;
    end;
    Result := Result + [AStack.Frames[mPosition]];
  end;
end;

function TallyOf(ATallies: TObjectDictionary<string, TMethodTally>; const AFrame: TAtlasProfileFrame): TMethodTally;
begin
  if not ATallies.TryGetValue(AFrame.Routine, Result) then
  begin
    Result := TMethodTally.Create(AFrame);
    ATallies.Add(AFrame.Routine, Result);
  end;
end;

/// <summary>Zählt einen Stapel: Eigenanteil beim innersten Rahmen, Gesamtanteil und Zeile beim ersten Vorkommen
/// jeder Methode.</summary>
procedure TallyStack(ATallies: TObjectDictionary<string, TMethodTally>; const AProfile: TAtlasProfile;
  const AFrames: TArray<Integer>; ACount: Integer);
var
  mSeen: TList<string>;
  mPosition: Integer;
  mFrame: TAtlasProfileFrame;
  mTally: TMethodTally;
begin
  mSeen := TList<string>.Create;
  try
    for mPosition := 0 to High(AFrames) do
    begin
      mFrame := AProfile.Frames[AFrames[mPosition]];
      mTally := TallyOf(ATallies, mFrame);
      if mPosition = 0 then
      begin
        Inc(mTally.Method.SelfCount, ACount);
      end;
      if not mSeen.Contains(mFrame.Routine) then
      begin
        mSeen.Add(mFrame.Routine);
        Inc(mTally.Method.TotalCount, ACount);
        mTally.CountLine(mFrame.Line, ACount);
      end;
    end;
  finally
    mSeen.Free;
  end;
end;

function CompareMethods(const ALeft, ARight: TAtlasProfileMethod): Integer;
begin
  Result := ARight.SelfCount - ALeft.SelfCount;
  if Result = 0 then
  begin
    Result := ARight.TotalCount - ALeft.TotalCount;
  end;
  if Result = 0 then
  begin
    Result := CompareStr(ALeft.Routine, ARight.Routine);
  end;
end;

class function TAtlasProfileAnalysis.Methods(const AProfile: TAtlasProfile;
  AOwnOnly: Boolean): TArray<TAtlasProfileMethod>;
var
  mTallies: TObjectDictionary<string, TMethodTally>;
  mStack: TAtlasProfileStack;
  mTally: TMethodTally;
  mList: TList<TAtlasProfileMethod>;
begin
  mTallies := TObjectDictionary<string, TMethodTally>.Create([doOwnsValues]);
  mList := TList<TAtlasProfileMethod>.Create;
  try
    for mStack in AProfile.Stacks do
    begin
      TallyStack(mTallies, AProfile, EffectiveFrames(AProfile, mStack, AOwnOnly), mStack.Count);
    end;
    for mTally in mTallies.Values do
    begin
      mTally.PickHotLine;
      mList.Add(mTally.Method);
    end;
    mList.Sort(TComparer<TAtlasProfileMethod>.Construct(CompareMethods));
    Result := mList.ToArray;
  finally
    mList.Free;
    mTallies.Free;
  end;
end;

function CompareLines(const ALeft, ARight: TAtlasProfileLine): Integer;
begin
  Result := CompareText(ALeft.FileName, ARight.FileName);
  if Result = 0 then
  begin
    Result := ALeft.Line - ARight.Line;
  end;
end;

/// <summary>Zählt die Zeilen eines Stapels, jede Datei-Zeile je Probe einmal.</summary>
procedure CountStackLines(ACounts: TDictionary<string, TAtlasProfileLine>; const AProfile: TAtlasProfile;
  const AFrames: TArray<Integer>; ACount: Integer);
var
  mSeen: TList<string>;
  mIndex: Integer;
  mKey: string;
  mLine: TAtlasProfileLine;
begin
  mSeen := TList<string>.Create;
  try
    for mIndex in AFrames do
    begin
      if (AProfile.Frames[mIndex].Line <= 0) or (AProfile.Frames[mIndex].FileName = '') then
      begin
        Continue;
      end;
      mKey := AProfile.Frames[mIndex].FileName + #1 + IntToStr(AProfile.Frames[mIndex].Line);
      if mSeen.Contains(mKey) then
      begin
        Continue;
      end;
      mSeen.Add(mKey);
      if not ACounts.TryGetValue(mKey, mLine) then
      begin
        mLine.FileName := AProfile.Frames[mIndex].FileName;
        mLine.Line := AProfile.Frames[mIndex].Line;
        mLine.Count := 0;
      end;
      Inc(mLine.Count, ACount);
      ACounts.AddOrSetValue(mKey, mLine);
    end;
  finally
    mSeen.Free;
  end;
end;

class function TAtlasProfileAnalysis.Lines(const AProfile: TAtlasProfile;
  AOwnOnly: Boolean): TArray<TAtlasProfileLine>;
var
  mCounts: TDictionary<string, TAtlasProfileLine>;
  mStack: TAtlasProfileStack;
  mList: TList<TAtlasProfileLine>;
begin
  mCounts := TDictionary<string, TAtlasProfileLine>.Create;
  mList := TList<TAtlasProfileLine>.Create;
  try
    for mStack in AProfile.Stacks do
    begin
      CountStackLines(mCounts, AProfile, EffectiveFrames(AProfile, mStack, AOwnOnly), mStack.Count);
    end;
    mList.AddRange(mCounts.Values);
    mList.Sort(TComparer<TAtlasProfileLine>.Construct(CompareLines));
    Result := mList.ToArray;
  finally
    mList.Free;
    mCounts.Free;
  end;
end;

function CompareDeltas(const ALeft, ARight: TAtlasProfileDelta): Integer;
begin
  Result := CompareValue(Abs(ARight.SelfChange), Abs(ALeft.SelfChange));
  if Result = 0 then
  begin
    Result := CompareStr(ALeft.Routine, ARight.Routine);
  end;
end;

/// <summary>Trägt die Methoden eines Laufs als „vorher“ (ABefore) oder „nachher“ in ADeltas ein.</summary>
procedure AddDeltas(ADeltas: TDictionary<string, TAtlasProfileDelta>; const AProfile: TAtlasProfile;
  AOwnOnly, ABefore: Boolean);
var
  mMethod: TAtlasProfileMethod;
  mDelta: TAtlasProfileDelta;
begin
  for mMethod in TAtlasProfileAnalysis.Methods(AProfile, AOwnOnly) do
  begin
    if not ADeltas.TryGetValue(mMethod.Routine, mDelta) then
    begin
      mDelta := Default(TAtlasProfileDelta);
      mDelta.Routine := mMethod.Routine;
      mDelta.IsLibrary := mMethod.IsLibrary;
    end;
    if ABefore then
    begin
      mDelta.SelfBefore := TAtlasProfileAnalysis.Percent(mMethod.SelfCount, AProfile.Samples);
      mDelta.TotalBefore := TAtlasProfileAnalysis.Percent(mMethod.TotalCount, AProfile.Samples);
    end
    else
    begin
      mDelta.SelfAfter := TAtlasProfileAnalysis.Percent(mMethod.SelfCount, AProfile.Samples);
      mDelta.TotalAfter := TAtlasProfileAnalysis.Percent(mMethod.TotalCount, AProfile.Samples);
    end;
    ADeltas.AddOrSetValue(mMethod.Routine, mDelta);
  end;
end;

class function TAtlasProfileAnalysis.Compare(const ABefore, AAfter: TAtlasProfile;
  AOwnOnly: Boolean): TArray<TAtlasProfileDelta>;
var
  mDeltas: TDictionary<string, TAtlasProfileDelta>;
  mList: TList<TAtlasProfileDelta>;
begin
  mDeltas := TDictionary<string, TAtlasProfileDelta>.Create;
  mList := TList<TAtlasProfileDelta>.Create;
  try
    AddDeltas(mDeltas, ABefore, AOwnOnly, True);
    AddDeltas(mDeltas, AAfter, AOwnOnly, False);
    mList.AddRange(mDeltas.Values);
    mList.Sort(TComparer<TAtlasProfileDelta>.Construct(CompareDeltas));
    Result := mList.ToArray;
  finally
    mList.Free;
    mDeltas.Free;
  end;
end;

end.
