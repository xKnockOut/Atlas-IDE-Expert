unit Atlas.Core.Hotspots.Model;

// Datenmodell des Fensters „Atlas-Hotspots“ (#1354), ohne VCL und Open Tools
// API:
// - TAtlasHotspotModel.Parse liest die Antwort von atlas.hotspots (Format 1
//   aus THotspotReport.Json des Servers) samt „keine Versionsverwaltung“ und
//   „ausgeschaltet“; Pfade werden mit "root" zu vollständigen Pfaden.
// - Filter wählt die Zeilen nach Unit- oder Methodennamen (Teiltext ohne
//   Groß-/Kleinschreibung).
// - TAtlasHotspotChart legt das Blasendiagramm an (x = Änderungen,
//   y = Komplexität, Radius nach Zeilen) und findet die Blase unter der Maus
//   (die kleinste, die den Punkt enthält).
// - TAtlasHotspotCommands baut die Argumente von atlas.hotspots und
//   atlas.hotspots.saveReport.

interface

uses
  System.SysUtils;

type
  TAtlasHotspotCommit = record
    Revision: string;
    Author: string;
    /// <summary>ISO-Zeitpunkt (UTC) wie vom Server.</summary>
    Date: string;
    Summary: string;
    /// <summary>-1 unbekannt.</summary>
    Added: Integer;
    Deleted: Integer;
    /// <summary>Kurzform: Git die ersten 7 Zeichen, SVN "r42".</summary>
    function ShortRevision(const AVcs: string): string;
  end;

  TAtlasHotspotEntry = record
    UnitName: string;
    /// <summary>Relativ zur Wurzel der Arbeitskopie mit "/".</summary>
    Path: string;
    /// <summary>Vollständiger Pfad.</summary>
    FileName: string;
    /// <summary>'' auf Unit-Ebene.</summary>
    Method: string;
    Line: Integer;
    EndLine: Integer;
    Changes: Integer;
    Authors: Integer;
    AuthorNames: TArray<string>;
    Added: Integer;
    Deleted: Integer;
    LastChange: string;
    Complexity: Integer;
    Lines: Integer;
    PastComplexity: Integer;
    /// <summary>rising, steady, falling, new oder unknown.</summary>
    Trend: string;
    Score: Double;
    History: TArray<TAtlasHotspotCommit>;
    /// <summary>Unit bzw. TFoo.Bar.</summary>
    function Caption: string;
  end;

  TAtlasHotspotPair = record
    FirstUnit: string;
    FirstPath: string;
    FirstFile: string;
    SecondUnit: string;
    SecondPath: string;
    SecondFile: string;
    Shared: Integer;
    FirstChanges: Integer;
    SecondChanges: Integer;
    Ratio: Double;
  end;

  TAtlasHotspotModel = record
  public const
    Format = 1;
  public
    Root: string;
    Title: string;
    /// <summary>git oder svn.</summary>
    Vcs: string;
    Head: string;
    Months: Integer;
    Since: string;
    Commits: Integer;
    /// <summary>unit oder method.</summary>
    Level: string;
    /// <summary>Der Server rechnet noch im Hintergrund ("pending"); später neu fragen.</summary>
    Pending: Boolean;
    Units: TArray<TAtlasHotspotEntry>;
    Methods: TArray<TAtlasHotspotEntry>;
    Coupling: TArray<TAtlasHotspotPair>;
    /// <summary>Antwort lesen. AEnabled = hotspots.enabled; AHasVcs False mit AMessage (Grund), wenn keine
    /// Versionsverwaltung greift. False bei unlesbarer Antwort.</summary>
    class function Parse(const AAnswer: string; out AModel: TAtlasHotspotModel; out AEnabled, AHasVcs: Boolean;
      out AMessage: string): Boolean; static;
    /// <summary>Zeilen der Ebene: Methoden bei "method", sonst Units.</summary>
    function Entries: TArray<TAtlasHotspotEntry>;
    /// <summary>Nummern der Zeilen von Entries, deren Unit- oder Methodenname AText enthält ('' = alle).</summary>
    function Filter(const AText: string): TArray<Integer>;
    /// <summary>Nummern der Kopplungspaare, deren Units AText enthalten ('' = alle).</summary>
    function FilterCoupling(const AText: string): TArray<Integer>;
  end;

  TAtlasHotspotBubble = record
    /// <summary>Nummer in Entries.</summary>
    Entry: Integer;
    X: Integer;
    Y: Integer;
    Radius: Integer;
  end;

  TAtlasHotspotChart = record
  public const
    /// <summary>Platz für die Achsen links und unten bzw. oben und rechts.</summary>
    MarginLeft = 44;
    MarginBottom = 28;
    MarginTop = 10;
    MarginRight = 14;
    MinRadius = 3;
    MaxRadius = 22;
    /// <summary>Höchstens so viele Blasen (die obersten der Rangliste).</summary>
    Limit = 200;
  public
    /// <summary>Blasen der Zeilen AShown (Nummern in AEntries) in einem Feld AWidth × AHeight; größte zuerst
    /// (gezeichnet wird in dieser Reihenfolge, kleine bleiben oben sichtbar). AScale: Bildpunkte je 96 dpi.</summary>
    class function Layout(const AEntries: TArray<TAtlasHotspotEntry>; const AShown: TArray<Integer>;
      AWidth, AHeight: Integer; AScale: Double): TArray<TAtlasHotspotBubble>; static;
    /// <summary>Zeile (Nummer in Entries) der kleinsten Blase, die den Punkt enthält; -1 ohne.</summary>
    class function HitTest(const ABubbles: TArray<TAtlasHotspotBubble>; X, Y: Integer): Integer; static;
    /// <summary>Farbe nach Wert als $00BBGGRR: grün (0) über gelb nach rot (1).</summary>
    class function ScoreColor(AScore: Double): Cardinal; static;
    /// <summary>Größte Änderungszahl bzw. Komplexität der Zeilen AShown (mindestens 1) für die Achsen.</summary>
    class procedure Extent(const AEntries: TArray<TAtlasHotspotEntry>; const AShown: TArray<Integer>;
      out AMaxChanges, AMaxComplexity: Integer); static;
  end;

  TAtlasHotspotCommands = class
  public const
    Command = 'atlas.hotspots';
    SaveCommand = 'atlas.hotspots.saveReport';
  public
    /// <summary>[uri, {"level", "format": "json", "refresh"}] für atlas.hotspots; ARefresh rechnet neu, auch wenn
    /// der Server ein Ergebnis zum Stand hat („Neu berechnen“).</summary>
    class function Arguments(const AProjectUri, ALevel: string; ARefresh: Boolean): string; static;
    /// <summary>[uri, Datei, {"level"}] für atlas.hotspots.saveReport.</summary>
    class function SaveArguments(const AProjectUri, AFileName, ALevel: string): string; static;
    /// <summary>Geschriebene Datei aus der Antwort von saveReport; '' bei Fehler oder solange gerechnet wird.
    /// </summary>
    class function SavedFile(const AAnswer: string): string; static;
    /// <summary>Antwort "pending": Der Server rechnet noch.</summary>
    class function IsPending(const AAnswer: string): Boolean; static;
    /// <summary>Spalte (ab 0) des Namens AName (TFoo.Bar bzw. Unit) in der Zeile ALineText: der letzte Teil als
    /// ganzes Wort, ohne Groß-/Kleinschreibung; -1, wenn er fehlt. Für „Auswirkungen anzeigen“.</summary>
    class function NameColumn(const ALineText, AName: string): Integer; static;
  end;

implementation

uses
  System.Math,
  System.JSON,
  System.Generics.Collections,
  System.Generics.Defaults;

function TextOf(const AObject: TJSONObject; const AName: string): string;
var
  mValue: TJSONValue;
begin
  Result := '';
  if AObject = nil then
    Exit;
  mValue := AObject.GetValue(AName);
  if mValue is TJSONString then
    Result := mValue.Value;
end;

function IntOf(const AObject: TJSONObject; const AName: string; ADefault: Integer): Integer;
var
  mValue: TJSONValue;
begin
  Result := ADefault;
  if AObject = nil then
    Exit;
  mValue := AObject.GetValue(AName);
  if mValue is TJSONNumber then
    Result := TJSONNumber(mValue).AsInt;
end;

function FloatOf(const AObject: TJSONObject; const AName: string): Double;
var
  mValue: TJSONValue;
begin
  Result := 0;
  if AObject = nil then
    Exit;
  mValue := AObject.GetValue(AName);
  if mValue is TJSONNumber then
    Result := TJSONNumber(mValue).AsDouble;
end;

function FlagOf(const AObject: TJSONObject; const AName: string): Boolean;
var
  mValue: TJSONValue;
begin
  Result := False;
  if AObject = nil then
    Exit;
  mValue := AObject.GetValue(AName);
  if mValue is TJSONBool then
    Result := TJSONBool(mValue).AsBoolean;
end;

function ArrayOf(const AObject: TJSONObject; const AName: string): TJSONArray;
var
  mValue: TJSONValue;
begin
  Result := nil;
  if AObject = nil then
    Exit;
  mValue := AObject.GetValue(AName);
  if mValue is TJSONArray then
    Result := TJSONArray(mValue);
end;

function ObjectOf(const AObject: TJSONObject; const AName: string): TJSONObject;
var
  mValue: TJSONValue;
begin
  Result := nil;
  if AObject = nil then
    Exit;
  mValue := AObject.GetValue(AName);
  if mValue is TJSONObject then
    Result := TJSONObject(mValue);
end;

/// <summary>Vollständiger Pfad aus Wurzel und relativem Pfad mit "/".</summary>
function FullPath(const ARoot, APath: string): string;
begin
  if ARoot = '' then
    Exit(APath);
  Result := IncludeTrailingPathDelimiter(ARoot) + StringReplace(APath, '/', PathDelim, [rfReplaceAll]);
end;

function ReadEntries(const AArray: TJSONArray; const ARoot: string): TArray<TAtlasHotspotEntry>;
var
  mIndex, mInner: Integer;
  mItem, mCommit: TJSONObject;
  mNames, mHistory: TJSONArray;
  mEntry: TAtlasHotspotEntry;
begin
  Result := nil;
  if AArray = nil then
    Exit;
  SetLength(Result, AArray.Count);
  for mIndex := 0 to AArray.Count - 1 do
  begin
    mEntry := Default(TAtlasHotspotEntry);
    if AArray.Items[mIndex] is TJSONObject then
    begin
      mItem := TJSONObject(AArray.Items[mIndex]);
      mEntry.UnitName := TextOf(mItem, 'unit');
      mEntry.Path := TextOf(mItem, 'path');
      mEntry.FileName := FullPath(ARoot, mEntry.Path);
      mEntry.Method := TextOf(mItem, 'method');
      mEntry.Line := IntOf(mItem, 'line', 1);
      mEntry.EndLine := IntOf(mItem, 'endLine', mEntry.Line);
      mEntry.Changes := IntOf(mItem, 'changes', 0);
      mEntry.Authors := IntOf(mItem, 'authors', 0);
      mNames := ArrayOf(mItem, 'authorNames');
      if mNames <> nil then
        for mInner := 0 to mNames.Count - 1 do
          if mNames.Items[mInner] is TJSONString then
            mEntry.AuthorNames := mEntry.AuthorNames + [mNames.Items[mInner].Value];
      mEntry.Added := IntOf(mItem, 'added', -1);
      mEntry.Deleted := IntOf(mItem, 'deleted', -1);
      mEntry.LastChange := TextOf(mItem, 'lastChange');
      mEntry.Complexity := IntOf(mItem, 'complexity', 0);
      mEntry.Lines := IntOf(mItem, 'lines', 0);
      mEntry.PastComplexity := IntOf(mItem, 'pastComplexity', -1);
      mEntry.Trend := TextOf(mItem, 'trend');
      mEntry.Score := FloatOf(mItem, 'score');
      mHistory := ArrayOf(mItem, 'history');
      if mHistory <> nil then
      begin
        SetLength(mEntry.History, mHistory.Count);
        for mInner := 0 to mHistory.Count - 1 do
        begin
          mEntry.History[mInner] := Default(TAtlasHotspotCommit);
          if not (mHistory.Items[mInner] is TJSONObject) then
            Continue;
          mCommit := TJSONObject(mHistory.Items[mInner]);
          mEntry.History[mInner].Revision := TextOf(mCommit, 'revision');
          mEntry.History[mInner].Author := TextOf(mCommit, 'author');
          mEntry.History[mInner].Date := TextOf(mCommit, 'date');
          mEntry.History[mInner].Summary := TextOf(mCommit, 'summary');
          mEntry.History[mInner].Added := IntOf(mCommit, 'added', -1);
          mEntry.History[mInner].Deleted := IntOf(mCommit, 'deleted', -1);
        end;
      end;
    end;
    Result[mIndex] := mEntry;
  end;
end;

{ TAtlasHotspotCommit }

function TAtlasHotspotCommit.ShortRevision(const AVcs: string): string;
begin
  if SameText(AVcs, 'svn') then
    Result := 'r' + Revision
  else
    Result := Copy(Revision, 1, 7);
end;

{ TAtlasHotspotEntry }

function TAtlasHotspotEntry.Caption: string;
begin
  if Method <> '' then
    Result := Method
  else
    Result := UnitName;
end;

{ TAtlasHotspotModel }

class function TAtlasHotspotModel.Parse(const AAnswer: string; out AModel: TAtlasHotspotModel;
  out AEnabled, AHasVcs: Boolean; out AMessage: string): Boolean;
var
  mRoot: TJSONValue;
  mAnswer, mData, mItem, mFirst, mSecond: TJSONObject;
  mItems: TJSONArray;
  mIndex: Integer;
begin
  AModel := Default(TAtlasHotspotModel);
  AEnabled := False;
  AHasVcs := False;
  AMessage := '';
  Result := False;
  mRoot := TJSONObject.ParseJSONValue(AAnswer);
  try
    if not (mRoot is TJSONObject) then
      Exit;
    mAnswer := TJSONObject(mRoot);
    if not (mAnswer.GetValue('enabled') is TJSONBool) then
      Exit;
    AEnabled := FlagOf(mAnswer, 'enabled');
    if not AEnabled then
      Exit(True);
    AHasVcs := FlagOf(mAnswer, 'vcs');
    if not AHasVcs then
    begin
      AMessage := TextOf(mAnswer, 'message');
      Exit(mAnswer.GetValue('vcs') is TJSONBool);
    end;
    AModel.Root := TextOf(mAnswer, 'root');
    if FlagOf(mAnswer, 'pending') then
    begin
      AModel.Pending := True;
      Exit(True);
    end;
    mData := ObjectOf(mAnswer, 'data');
    if (mData = nil) or (IntOf(mData, 'format', 0) <> Format) then
      Exit;
    AModel.Title := TextOf(mData, 'title');
    AModel.Vcs := TextOf(mData, 'vcs');
    AModel.Head := TextOf(mData, 'head');
    AModel.Months := IntOf(mData, 'months', 0);
    AModel.Since := TextOf(mData, 'since');
    AModel.Commits := IntOf(mData, 'commits', 0);
    AModel.Level := TextOf(mData, 'level');
    AModel.Units := ReadEntries(ArrayOf(mData, 'units'), AModel.Root);
    AModel.Methods := ReadEntries(ArrayOf(mData, 'methods'), AModel.Root);
    mItems := ArrayOf(mData, 'coupling');
    if mItems <> nil then
    begin
      SetLength(AModel.Coupling, mItems.Count);
      for mIndex := 0 to mItems.Count - 1 do
      begin
        AModel.Coupling[mIndex] := Default(TAtlasHotspotPair);
        if not (mItems.Items[mIndex] is TJSONObject) then
          Continue;
        mItem := TJSONObject(mItems.Items[mIndex]);
        mFirst := ObjectOf(mItem, 'first');
        mSecond := ObjectOf(mItem, 'second');
        AModel.Coupling[mIndex].FirstUnit := TextOf(mFirst, 'unit');
        AModel.Coupling[mIndex].FirstPath := TextOf(mFirst, 'path');
        AModel.Coupling[mIndex].FirstFile := FullPath(AModel.Root, AModel.Coupling[mIndex].FirstPath);
        AModel.Coupling[mIndex].SecondUnit := TextOf(mSecond, 'unit');
        AModel.Coupling[mIndex].SecondPath := TextOf(mSecond, 'path');
        AModel.Coupling[mIndex].SecondFile := FullPath(AModel.Root, AModel.Coupling[mIndex].SecondPath);
        AModel.Coupling[mIndex].Shared := IntOf(mItem, 'shared', 0);
        AModel.Coupling[mIndex].FirstChanges := IntOf(mItem, 'firstChanges', 0);
        AModel.Coupling[mIndex].SecondChanges := IntOf(mItem, 'secondChanges', 0);
        AModel.Coupling[mIndex].Ratio := FloatOf(mItem, 'ratio');
      end;
    end;
    Result := True;
  finally
    mRoot.Free;
  end;
end;

function TAtlasHotspotModel.Entries: TArray<TAtlasHotspotEntry>;
begin
  if SameText(Level, 'method') then
    Result := Methods
  else
    Result := Units;
end;

function TAtlasHotspotModel.Filter(const AText: string): TArray<Integer>;
var
  mEntries: TArray<TAtlasHotspotEntry>;
  mIndex: Integer;
  mText: string;
begin
  Result := nil;
  mText := LowerCase(Trim(AText));
  mEntries := Entries;
  for mIndex := 0 to High(mEntries) do
    if (mText = '') or (Pos(mText, LowerCase(mEntries[mIndex].UnitName)) > 0) or
      (Pos(mText, LowerCase(mEntries[mIndex].Method)) > 0) then
      Result := Result + [mIndex];
end;

function TAtlasHotspotModel.FilterCoupling(const AText: string): TArray<Integer>;
var
  mIndex: Integer;
  mText: string;
begin
  Result := nil;
  mText := LowerCase(Trim(AText));
  for mIndex := 0 to High(Coupling) do
    if (mText = '') or (Pos(mText, LowerCase(Coupling[mIndex].FirstUnit)) > 0) or
      (Pos(mText, LowerCase(Coupling[mIndex].SecondUnit)) > 0) then
      Result := Result + [mIndex];
end;

{ TAtlasHotspotChart }

class procedure TAtlasHotspotChart.Extent(const AEntries: TArray<TAtlasHotspotEntry>; const AShown: TArray<Integer>;
  out AMaxChanges, AMaxComplexity: Integer);
var
  mIndex: Integer;
begin
  AMaxChanges := 1;
  AMaxComplexity := 1;
  for mIndex := 0 to Min(Length(AShown), Limit) - 1 do
  begin
    AMaxChanges := Max(AMaxChanges, AEntries[AShown[mIndex]].Changes);
    AMaxComplexity := Max(AMaxComplexity, AEntries[AShown[mIndex]].Complexity);
  end;
end;

class function TAtlasHotspotChart.Layout(const AEntries: TArray<TAtlasHotspotEntry>; const AShown: TArray<Integer>;
  AWidth, AHeight: Integer; AScale: Double): TArray<TAtlasHotspotBubble>;
var
  mList: TList<TAtlasHotspotBubble>;
  mBubble: TAtlasHotspotBubble;
  mMaxChanges, mMaxComplexity, mMaxLines, mIndex, mLeft, mBottom, mTop, mRight: Integer;
  mEntry: TAtlasHotspotEntry;
begin
  Result := nil;
  if (AWidth <= 0) or (AHeight <= 0) or (Length(AShown) = 0) then
    Exit;
  Extent(AEntries, AShown, mMaxChanges, mMaxComplexity);
  mMaxLines := 1;
  for mIndex := 0 to Min(Length(AShown), Limit) - 1 do
    mMaxLines := Max(mMaxLines, AEntries[AShown[mIndex]].Lines);
  mLeft := Round(MarginLeft * AScale);
  mBottom := AHeight - Round(MarginBottom * AScale);
  mTop := Round(MarginTop * AScale);
  mRight := AWidth - Round(MarginRight * AScale);
  if (mRight <= mLeft) or (mBottom <= mTop) then
    Exit;
  mList := TList<TAtlasHotspotBubble>.Create;
  try
    for mIndex := 0 to Min(Length(AShown), Limit) - 1 do
    begin
      mEntry := AEntries[AShown[mIndex]];
      mBubble.Entry := AShown[mIndex];
      mBubble.X := mLeft + Round((mRight - mLeft) * mEntry.Changes / mMaxChanges);
      mBubble.Y := mBottom - Round((mBottom - mTop) * mEntry.Complexity / mMaxComplexity);
      mBubble.Radius := Round((MinRadius + (MaxRadius - MinRadius) * Sqrt(Max(0, mEntry.Lines) / mMaxLines)) * AScale);
      mList.Add(mBubble);
    end;
    // Größte zuerst; bei Gleichstand die Rangfolge, damit die Reihenfolge eindeutig bleibt.
    mList.Sort(TComparer<TAtlasHotspotBubble>.Construct(
      function(const ALeft, ARight: TAtlasHotspotBubble): Integer
      begin
        Result := ARight.Radius - ALeft.Radius;
        if Result = 0 then
          Result := ARight.Entry - ALeft.Entry;
      end));
    Result := mList.ToArray;
  finally
    mList.Free;
  end;
end;

class function TAtlasHotspotChart.HitTest(const ABubbles: TArray<TAtlasHotspotBubble>; X, Y: Integer): Integer;
var
  mIndex, mBest: Integer;
  mBubble: TAtlasHotspotBubble;
begin
  Result := -1;
  mBest := MaxInt;
  // Die zuletzt gezeichnete (kleinere) liegt oben.
  for mIndex := High(ABubbles) downto 0 do
  begin
    mBubble := ABubbles[mIndex];
    if (Sqr(X - mBubble.X) + Sqr(Y - mBubble.Y) <= Sqr(mBubble.Radius)) and (mBubble.Radius < mBest) then
    begin
      mBest := mBubble.Radius;
      Result := mBubble.Entry;
    end;
  end;
end;

class function TAtlasHotspotChart.ScoreColor(AScore: Double): Cardinal;
var
  mScore: Double;
  mRed, mGreen: Integer;
begin
  // Grün → Gelb → Rot wie im HTML-Bericht (hsl 120 → 0).
  mScore := EnsureRange(AScore, 0, 1);
  if mScore < 0.5 then
  begin
    mRed := Round(200 * mScore * 2);
    mGreen := 170;
  end
  else
  begin
    mRed := 200;
    mGreen := Round(170 * (1 - mScore) * 2);
  end;
  Result := Cardinal(mRed) or (Cardinal(mGreen) shl 8) or (Cardinal(40) shl 16);
end;

{ TAtlasHotspotCommands }

class function TAtlasHotspotCommands.Arguments(const AProjectUri, ALevel: string; ARefresh: Boolean): string;
var
  mItems: TJSONArray;
  mOption: TJSONObject;
begin
  mItems := TJSONArray.Create;
  try
    mItems.Add(AProjectUri);
    mOption := TJSONObject.Create;
    mOption.AddPair('level', ALevel);
    mOption.AddPair('format', 'json');
    if ARefresh then
      mOption.AddPair('refresh', TJSONBool.Create(True));
    mItems.AddElement(mOption);
    Result := mItems.ToJSON;
  finally
    mItems.Free;
  end;
end;

class function TAtlasHotspotCommands.SaveArguments(const AProjectUri, AFileName, ALevel: string): string;
var
  mItems: TJSONArray;
  mOption: TJSONObject;
begin
  mItems := TJSONArray.Create;
  try
    mItems.Add(AProjectUri);
    mItems.Add(AFileName);
    mOption := TJSONObject.Create;
    mOption.AddPair('level', ALevel);
    mItems.AddElement(mOption);
    Result := mItems.ToJSON;
  finally
    mItems.Free;
  end;
end;

class function TAtlasHotspotCommands.SavedFile(const AAnswer: string): string;
var
  mRoot: TJSONValue;
begin
  Result := '';
  mRoot := TJSONObject.ParseJSONValue(AAnswer);
  try
    if mRoot is TJSONObject then
      Result := TextOf(TJSONObject(mRoot), 'file');
  finally
    mRoot.Free;
  end;
end;

class function TAtlasHotspotCommands.IsPending(const AAnswer: string): Boolean;
var
  mRoot: TJSONValue;
begin
  mRoot := TJSONObject.ParseJSONValue(AAnswer);
  try
    Result := (mRoot is TJSONObject) and FlagOf(TJSONObject(mRoot), 'pending');
  finally
    mRoot.Free;
  end;
end;

function IsNameChar(AChar: Char): Boolean;
begin
  Result := CharInSet(AChar, ['A'..'Z', 'a'..'z', '0'..'9', '_']) or (Ord(AChar) > 127);
end;

class function TAtlasHotspotCommands.NameColumn(const ALineText, AName: string): Integer;
var
  mName, mLine: string;
  mDot, mFrom, mFound: Integer;
begin
  Result := -1;
  mName := Trim(AName);
  mDot := mName.LastIndexOf('.');
  if mDot >= 0 then
    mName := mName.Substring(mDot + 1);
  if mName = '' then
    Exit;
  mLine := LowerCase(ALineText);
  mName := LowerCase(mName);
  mFrom := 0;
  while True do
  begin
    mFound := mLine.IndexOf(mName, mFrom);
    if mFound < 0 then
      Exit;
    if ((mFound = 0) or not IsNameChar(mLine.Chars[mFound - 1])) and
      ((mFound + Length(mName) >= Length(mLine)) or not IsNameChar(mLine.Chars[mFound + Length(mName)])) then
      Exit(mFound);
    mFrom := mFound + 1;
  end;
end;

end.
