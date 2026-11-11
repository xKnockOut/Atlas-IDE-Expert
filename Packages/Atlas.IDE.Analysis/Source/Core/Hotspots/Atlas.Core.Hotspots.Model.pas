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
    cFormat = 1;
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
    cMarginLeft = 44;
    cMarginBottom = 28;
    cMarginTop = 10;
    cMarginRight = 14;
    cMinRadius = 3;
    cMaxRadius = 22;
    /// <summary>Höchstens so viele Blasen (die obersten der Rangliste).</summary>
    cLimit = 200;
  public
    /// <summary>Blasen der Zeilen AShown (Nummern in AEntries) in einem Feld AWidth × AHeight; größte zuerst
    /// (gezeichnet wird in dieser Reihenfolge, kleine bleiben oben sichtbar). AScale: Bildpunkte je 96 dpi.</summary>
    class function Layout(const AEntries: TArray<TAtlasHotspotEntry>; const AShown: TArray<Integer>;
      AWidth, AHeight: Integer; AScale: Double): TArray<TAtlasHotspotBubble>; static;
    /// <summary>Zeile (Nummer in Entries) der kleinsten Blase, die den Punkt enthält; -1 ohne.</summary>
    class function HitTest(const ABubbles: TArray<TAtlasHotspotBubble>; AX, AY: Integer): Integer; static;
    /// <summary>Farbe nach Wert als $00BBGGRR: grün (0) über gelb nach rot (1).</summary>
    class function ScoreColor(AScore: Double): Cardinal; static;
    /// <summary>Größte Änderungszahl bzw. Komplexität der Zeilen AShown (mindestens 1) für die Achsen.</summary>
    class procedure Extent(const AEntries: TArray<TAtlasHotspotEntry>; const AShown: TArray<Integer>;
      out AMaxChanges, AMaxComplexity: Integer); static;
  end;

  TAtlasHotspotCommands = class
  public const
    cCommand = 'atlas.hotspots';
    cSaveCommand = 'atlas.hotspots.saveReport';
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
  System.Generics.Defaults,
  Atlas.Text.Json;

/// <summary>Vollständiger Pfad aus Wurzel und relativem Pfad mit "/".</summary>
function FullPath(const ARoot, APath: string): string;
begin
  if ARoot = '' then
  begin
    Exit(APath);
  end;
  Result := IncludeTrailingPathDelimiter(ARoot) + StringReplace(APath, '/', PathDelim, [rfReplaceAll]);
end;

function ReadNames(const AArray: TJSONArray): TArray<string>;
var
  mIndex: Integer;
begin
  Result := nil;
  if AArray = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to AArray.Count - 1 do
  begin
    if AArray.Items[mIndex] is TJSONString then
    begin
      Result := Result + [AArray.Items[mIndex].Value];
    end;
  end;
end;

function ReadCommit(const AValue: TJSONValue): TAtlasHotspotCommit;
var
  mCommit: TJSONObject;
begin
  Result := Default(TAtlasHotspotCommit);
  if not (AValue is TJSONObject) then
  begin
    Exit;
  end;
  mCommit := TJSONObject(AValue);
  Result.Revision := TJsonRead.Text(mCommit, 'revision');
  Result.Author := TJsonRead.Text(mCommit, 'author');
  Result.Date := TJsonRead.Text(mCommit, 'date');
  Result.Summary := TJsonRead.Text(mCommit, 'summary');
  Result.Added := TJsonRead.IntOr(mCommit, 'added', -1);
  Result.Deleted := TJsonRead.IntOr(mCommit, 'deleted', -1);
end;

function ReadHistory(const AArray: TJSONArray): TArray<TAtlasHotspotCommit>;
var
  mIndex: Integer;
begin
  Result := nil;
  if AArray = nil then
  begin
    Exit;
  end;
  SetLength(Result, AArray.Count);
  for mIndex := 0 to AArray.Count - 1 do
  begin
    Result[mIndex] := ReadCommit(AArray.Items[mIndex]);
  end;
end;

function ReadEntry(const AValue: TJSONValue; const ARoot: string): TAtlasHotspotEntry;
var
  mItem: TJSONObject;
begin
  Result := Default(TAtlasHotspotEntry);
  if not (AValue is TJSONObject) then
  begin
    Exit;
  end;
  mItem := TJSONObject(AValue);
  Result.UnitName := TJsonRead.Text(mItem, 'unit');
  Result.Path := TJsonRead.Text(mItem, 'path');
  Result.FileName := FullPath(ARoot, Result.Path);
  Result.Method := TJsonRead.Text(mItem, 'method');
  Result.Line := TJsonRead.IntOr(mItem, 'line', 1);
  Result.EndLine := TJsonRead.IntOr(mItem, 'endLine', Result.Line);
  Result.Changes := TJsonRead.IntOr(mItem, 'changes', 0);
  Result.Authors := TJsonRead.IntOr(mItem, 'authors', 0);
  Result.AuthorNames := ReadNames(TJsonRead.Items(mItem, 'authorNames'));
  Result.Added := TJsonRead.IntOr(mItem, 'added', -1);
  Result.Deleted := TJsonRead.IntOr(mItem, 'deleted', -1);
  Result.LastChange := TJsonRead.Text(mItem, 'lastChange');
  Result.Complexity := TJsonRead.IntOr(mItem, 'complexity', 0);
  Result.Lines := TJsonRead.IntOr(mItem, 'lines', 0);
  Result.PastComplexity := TJsonRead.IntOr(mItem, 'pastComplexity', -1);
  Result.Trend := TJsonRead.Text(mItem, 'trend');
  Result.Score := TJsonRead.Float(mItem, 'score');
  Result.History := ReadHistory(TJsonRead.Items(mItem, 'history'));
end;

function ReadEntries(const AArray: TJSONArray; const ARoot: string): TArray<TAtlasHotspotEntry>;
var
  mIndex: Integer;
begin
  Result := nil;
  if AArray = nil then
  begin
    Exit;
  end;
  SetLength(Result, AArray.Count);
  for mIndex := 0 to AArray.Count - 1 do
  begin
    Result[mIndex] := ReadEntry(AArray.Items[mIndex], ARoot);
  end;
end;

{ TAtlasHotspotCommit }

function TAtlasHotspotCommit.ShortRevision(const AVcs: string): string;
begin
  if SameText(AVcs, 'svn') then
  begin
    Result := 'r' + Revision;
  end
  else
  begin
    Result := Copy(Revision, 1, 7);
  end;
end;

{ TAtlasHotspotEntry }

function TAtlasHotspotEntry.Caption: string;
begin
  if Method <> '' then
  begin
    Result := Method;
  end
  else
  begin
    Result := UnitName;
  end;
end;

{ TAtlasHotspotModel }

function ReadPair(const AValue: TJSONValue; const ARoot: string): TAtlasHotspotPair;
var
  mItem, mFirst, mSecond: TJSONObject;
begin
  Result := Default(TAtlasHotspotPair);
  if not (AValue is TJSONObject) then
  begin
    Exit;
  end;
  mItem := TJSONObject(AValue);
  mFirst := TJsonRead.Obj(mItem, 'first');
  mSecond := TJsonRead.Obj(mItem, 'second');
  Result.FirstUnit := TJsonRead.Text(mFirst, 'unit');
  Result.FirstPath := TJsonRead.Text(mFirst, 'path');
  Result.FirstFile := FullPath(ARoot, Result.FirstPath);
  Result.SecondUnit := TJsonRead.Text(mSecond, 'unit');
  Result.SecondPath := TJsonRead.Text(mSecond, 'path');
  Result.SecondFile := FullPath(ARoot, Result.SecondPath);
  Result.Shared := TJsonRead.IntOr(mItem, 'shared', 0);
  Result.FirstChanges := TJsonRead.IntOr(mItem, 'firstChanges', 0);
  Result.SecondChanges := TJsonRead.IntOr(mItem, 'secondChanges', 0);
  Result.Ratio := TJsonRead.Float(mItem, 'ratio');
end;

function ReadCoupling(const AArray: TJSONArray; const ARoot: string): TArray<TAtlasHotspotPair>;
var
  mIndex: Integer;
begin
  Result := nil;
  if AArray = nil then
  begin
    Exit;
  end;
  SetLength(Result, AArray.Count);
  for mIndex := 0 to AArray.Count - 1 do
  begin
    Result[mIndex] := ReadPair(AArray.Items[mIndex], ARoot);
  end;
end;

/// <summary>Daten der Auswertung; False ohne Daten oder bei einem anderen Format.</summary>
function ReadData(const AData: TJSONObject; var AModel: TAtlasHotspotModel): Boolean;
begin
  Result := (AData <> nil) and (TJsonRead.IntOr(AData, 'format', 0) = TAtlasHotspotModel.cFormat);
  if not Result then
  begin
    Exit;
  end;
  AModel.Title := TJsonRead.Text(AData, 'title');
  AModel.Vcs := TJsonRead.Text(AData, 'vcs');
  AModel.Head := TJsonRead.Text(AData, 'head');
  AModel.Months := TJsonRead.IntOr(AData, 'months', 0);
  AModel.Since := TJsonRead.Text(AData, 'since');
  AModel.Commits := TJsonRead.IntOr(AData, 'commits', 0);
  AModel.Level := TJsonRead.Text(AData, 'level');
  AModel.Units := ReadEntries(TJsonRead.Items(AData, 'units'), AModel.Root);
  AModel.Methods := ReadEntries(TJsonRead.Items(AData, 'methods'), AModel.Root);
  AModel.Coupling := ReadCoupling(TJsonRead.Items(AData, 'coupling'), AModel.Root);
end;

function ReadAnswer(const AAnswer: TJSONObject; var AModel: TAtlasHotspotModel; var AEnabled, AHasVcs: Boolean;
  var AMessage: string): Boolean;
begin
  if not (AAnswer.GetValue('enabled') is TJSONBool) then
  begin
    Exit(False);
  end;
  AEnabled := TJsonRead.Flag(AAnswer, 'enabled');
  if not AEnabled then
  begin
    Exit(True);
  end;
  AHasVcs := TJsonRead.Flag(AAnswer, 'vcs');
  if not AHasVcs then
  begin
    AMessage := TJsonRead.Text(AAnswer, 'message');
    Exit(AAnswer.GetValue('vcs') is TJSONBool);
  end;
  AModel.Root := TJsonRead.Text(AAnswer, 'root');
  AModel.Pending := TJsonRead.Flag(AAnswer, 'pending');
  Result := AModel.Pending or ReadData(TJsonRead.Obj(AAnswer, 'data'), AModel);
end;

class function TAtlasHotspotModel.Parse(const AAnswer: string; out AModel: TAtlasHotspotModel;
  out AEnabled, AHasVcs: Boolean; out AMessage: string): Boolean;
var
  mRoot: TJSONValue;
begin
  AModel := Default(TAtlasHotspotModel);
  AEnabled := False;
  AHasVcs := False;
  AMessage := '';
  mRoot := TJSONObject.ParseJSONValue(AAnswer);
  try
    Result := (mRoot is TJSONObject) and ReadAnswer(TJSONObject(mRoot), AModel, AEnabled, AHasVcs, AMessage);
  finally
    mRoot.Free;
  end;
end;

function TAtlasHotspotModel.Entries: TArray<TAtlasHotspotEntry>;
begin
  if SameText(Level, 'method') then
  begin
    Result := Methods;
  end
  else
  begin
    Result := Units;
  end;
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
  begin
    if (mText = '') or (Pos(mText, LowerCase(mEntries[mIndex].UnitName)) > 0) or
      (Pos(mText, LowerCase(mEntries[mIndex].Method)) > 0) then
    begin
      Result := Result + [mIndex];
    end;
  end;
end;

function TAtlasHotspotModel.FilterCoupling(const AText: string): TArray<Integer>;
var
  mIndex: Integer;
  mText: string;
begin
  Result := nil;
  mText := LowerCase(Trim(AText));
  for mIndex := 0 to High(Coupling) do
  begin
    if (mText = '') or (Pos(mText, LowerCase(Coupling[mIndex].FirstUnit)) > 0) or
      (Pos(mText, LowerCase(Coupling[mIndex].SecondUnit)) > 0) then
    begin
      Result := Result + [mIndex];
    end;
  end;
end;

{ TAtlasHotspotChart }

class procedure TAtlasHotspotChart.Extent(const AEntries: TArray<TAtlasHotspotEntry>; const AShown: TArray<Integer>;
  out AMaxChanges, AMaxComplexity: Integer);
var
  mIndex: Integer;
begin
  AMaxChanges := 1;
  AMaxComplexity := 1;
  for mIndex := 0 to Min(Length(AShown), cLimit) - 1 do
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
  begin
    Exit;
  end;
  Extent(AEntries, AShown, mMaxChanges, mMaxComplexity);
  mMaxLines := 1;
  for mIndex := 0 to Min(Length(AShown), cLimit) - 1 do
  begin
    mMaxLines := Max(mMaxLines, AEntries[AShown[mIndex]].Lines);
  end;
  mLeft := Round(cMarginLeft * AScale);
  mBottom := AHeight - Round(cMarginBottom * AScale);
  mTop := Round(cMarginTop * AScale);
  mRight := AWidth - Round(cMarginRight * AScale);
  if (mRight <= mLeft) or (mBottom <= mTop) then
  begin
    Exit;
  end;
  mList := TList<TAtlasHotspotBubble>.Create;
  try
    for mIndex := 0 to Min(Length(AShown), cLimit) - 1 do
    begin
      mEntry := AEntries[AShown[mIndex]];
      mBubble.Entry := AShown[mIndex];
      mBubble.X := mLeft + Round((mRight - mLeft) * mEntry.Changes / mMaxChanges);
      mBubble.Y := mBottom - Round((mBottom - mTop) * mEntry.Complexity / mMaxComplexity);
      mBubble.Radius := Round((cMinRadius + (cMaxRadius - cMinRadius) * Sqrt(Max(0, mEntry.Lines) / mMaxLines)) *
        AScale);
      mList.Add(mBubble);
    end;
    // Größte zuerst; bei Gleichstand die Rangfolge, damit die Reihenfolge eindeutig bleibt.
    mList.Sort(TComparer<TAtlasHotspotBubble>.Construct(
      function(const ALeft, ARight: TAtlasHotspotBubble): Integer
      begin
        Result := ARight.Radius - ALeft.Radius;
        if Result = 0 then
        begin
          Result := ARight.Entry - ALeft.Entry;
        end;
      end));
    Result := mList.ToArray;
  finally
    mList.Free;
  end;
end;

class function TAtlasHotspotChart.HitTest(const ABubbles: TArray<TAtlasHotspotBubble>; AX, AY: Integer): Integer;
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
    if (Sqr(AX - mBubble.X) + Sqr(AY - mBubble.Y) <= Sqr(mBubble.Radius)) and (mBubble.Radius < mBest) then
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
    begin
      mOption.AddPair('refresh', TJSONBool.Create(True));
    end;
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
    begin
      Result := TJsonRead.Text(TJSONObject(mRoot), 'file');
    end;
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
    Result := (mRoot is TJSONObject) and TJsonRead.Flag(TJSONObject(mRoot), 'pending');
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
  begin
    mName := mName.Substring(mDot + 1);
  end;
  if mName = '' then
  begin
    Exit;
  end;
  mLine := LowerCase(ALineText);
  mName := LowerCase(mName);
  mFrom := 0;
  while True do
  begin
    mFound := mLine.IndexOf(mName, mFrom);
    if mFound < 0 then
    begin
      Exit;
    end;
    if ((mFound = 0) or not IsNameChar(mLine.Chars[mFound - 1])) and
      ((mFound + Length(mName) >= Length(mLine)) or not IsNameChar(mLine.Chars[mFound + Length(mName)])) then
    begin
      Exit(mFound);
    end;
    mFrom := mFound + 1;
  end;
end;

end.
