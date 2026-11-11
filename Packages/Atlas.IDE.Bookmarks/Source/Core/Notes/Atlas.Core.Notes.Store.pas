unit Atlas.Core.Notes.Store;

// Persönliche Notizen an Codezeilen (#545), ohne VCL und Open Tools API:
// Notizbuch je Projekt (Anlegen, Ändern, Löschen, Neuverankern, Liste nach
// Datei mit verwaisten Notizen am Ende) und die Ablage. Die Notizen landen
// nie im Quelltext und nie im Projektordner, deshalb zeigt `git status` nach
// dem Anlegen nichts.
//
// Ablage: %LOCALAPPDATA%\Atlas\Notes\<schlüssel>.json je Projekt. Der
// Schlüssel ist derselbe wie bei der Projekt-Zusammenfassung (#592,
// TAtlasProjectSummaries.KeyOf über den Pfad der Projektdatei). Lesbar ohne
// laufenden Server und ohne geöffnetes Projekt (Load, Parse, LoadAll), etwa
// für „Weiterarbeiten“ auf der Willkommensseite (#755).
//
// Format 1 (UTF-8 ohne BOM; Zeiten in UTC wie "2026-10-15T09:30:00Z"):
//   {
//     "format": 1,
//     "project": "C:\\Projekte\\Demo.dproj",
//     "notes": [
//       {"id": "5f0c…", "file": "C:\\Projekte\\Kunde.pas", "line": 42,
//        "text": "hier noch Rundung prüfen\nzweite Zeile",
//        "lineText": "Result := Round(Betrag);",
//        "before": ["begin", "…"], "after": ["end;", "…"],
//        "created": "…", "changed": "…", "orphaned": true}
//     ]
//   }
// "line" zählt ab 1 (wie im Editor). "lineText", "before" und "after" sind
// die normierte Zeile und ihre Nachbarn (die nächste zuerst) für die
// Verankerung (Atlas.Core.Editor.LineAnchor). "orphaned" steht nur bei verwaisten
// Notizen. Unbekannte Felder (oben und je Notiz) bleiben beim Schreiben
// erhalten; "format" steigt nur bei einer inkompatiblen Änderung, eine Datei
// mit höherem Format wird weder gelesen noch überschrieben. Ein leeres
// Notizbuch löscht seine Datei.
// Lesen und Schreiben über TAtlasDataFile: atomar ersetzt
// (früher Löschen und Umbenennen), eine unbrauchbare Datei liegt danach als
// .defekt daneben; eine beim Lesen gesperrte merkt sich das Notizbuch
// (KeptFile), und Save überschreibt sie nicht.
// Nicht threadsicher: Die IDE liest und schreibt nur im Hauptthread.

interface

uses
  System.SysUtils,
  Atlas.Core.Editor.LineAnchor;

type
  TAtlasNote = record
    /// <summary>Eindeutig im Notizbuch (GUID ohne Klammern, klein).</summary>
    Id: string;
    /// <summary>Vollständiger Pfad der Datei.</summary>
    FileName: string;
    /// <summary>Text der Notiz, ein- oder mehrzeilig (Zeilen mit #10 getrennt).</summary>
    Text: string;
    Anchor: TAtlasLineAnchor;
    /// <summary>UTC.</summary>
    Created: TDateTime;
    /// <summary>Letzte Änderung des Textes (UTC).</summary>
    Changed: TDateTime;
    /// <summary>Die Codezeile ist nicht mehr zuordenbar.</summary>
    Orphaned: Boolean;
    /// <summary>Unbekannte Felder als JSON-Objekt; bleiben beim Schreiben erhalten.</summary>
    Extra: string;
    /// <summary>Zeile, 0-basiert.</summary>
    function Line: Integer;
    /// <summary>Erste nicht leere Zeile des Textes, mit „…“, wenn mehr folgt.</summary>
    function Title: string;
  end;

  /// <summary>Gruppe der Liste: eine Datei oder (Orphaned) alle verwaisten Notizen.</summary>
  TAtlasNoteGroup = record
    FileName: string;
    Orphaned: Boolean;
    Notes: TArray<TAtlasNote>;
  end;

  /// <summary>Notizen eines Projekts.</summary>
  TAtlasNoteBook = record
    /// <summary>Pfad der Projektdatei.</summary>
    Project: string;
    Notes: TArray<TAtlasNote>;
    /// <summary>Gelesener Text der Datei; ToJson behält daraus unbekannte Felder.</summary>
    Raw: string;
    /// <summary>Vorhandene Datei, die beim Lesen gesperrt war: Save überschreibt sie nicht, sonst gingen ihre
    /// Notizen verloren. '' sonst.</summary>
    KeptFile: string;
    class function Create(const AProject: string): TAtlasNoteBook; static;
    function Count: Integer;
    function IndexOf(const AId: string): Integer;
    /// <summary>Erste nicht verwaiste Notiz an ALine (0-basiert) in AFileName; -1 ohne.</summary>
    function IndexAt(const AFileName: string; ALine: Integer): Integer;
    /// <summary>Alle nicht verwaisten Notizen an ALine.</summary>
    function AtLine(const AFileName: string; ALine: Integer): TArray<TAtlasNote>;
    /// <summary>Alle Notizen der Datei, auch verwaiste.</summary>
    function ForFile(const AFileName: string): TArray<TAtlasNote>;
    /// <summary>Dateien mit Notizen, jede einmal.</summary>
    function Files: TArray<string>;
    function OrphanCount: Integer;
    /// <summary>Neue Notiz an ALine von ALines (Text der Datei); liefert ihre Kennung.</summary>
    function Add(const AFileName: string; const ALines: TArray<string>; ALine: Integer; const AText: string;
      ANowUtc: TDateTime): string;
    /// <summary>Text ändern; False ohne diese Notiz.</summary>
    function SetText(const AId, AText: string; ANowUtc: TDateTime): Boolean;
    function Remove(const AId: string): Boolean;
    /// <summary>Notizen von AFileName gegen dessen aktuellen Text neu verankern (folgen eingefügten und
    /// gelöschten Zeilen, merken geänderte Zeilen, werden verwaist bzw. wieder gefunden). True, wenn sich
    /// etwas geändert hat.</summary>
    function Relocate(const AFileName: string; const ALines: TArray<string>): Boolean;
    /// <summary>Die Datei fehlt: alle ihre Notizen verwaist. True, wenn sich etwas geändert hat.</summary>
    function OrphanFile(const AFileName: string): Boolean;
    /// <summary>Liste: Dateien nach Name, darin nach Zeile; verwaiste Notizen in einer Gruppe am Ende.</summary>
    function Groups: TArray<TAtlasNoteGroup>;
  end;

  TAtlasNotes = class
  public const
    /// <summary>Format, das diese Fassung liest und schreibt.</summary>
    cFormat = 1;
    /// <summary>Unterordner von %LOCALAPPDATA%\Atlas.</summary>
    cFolderName = 'Notes';
  public
    /// <summary>%LOCALAPPDATA%\Atlas\Notes; '' ohne LOCALAPPDATA.</summary>
    class function DefaultFolder: string; static;
    /// <summary>AFolder\&lt;schlüssel&gt;.json; Schlüssel wie TAtlasProjectSummaries.KeyOf.</summary>
    class function FileFor(const AFolder, AProject: string): string; static;
    /// <summary>Gleiche Datei: Groß-/Kleinschreibung (ASCII), „/“ und „\“ sowie Leerraum am Rand egal.</summary>
    class function SameFile(const A, B: string): Boolean; static;
    class function NewId: string; static;
    /// <summary>Liest AJson. False bei ungültigem Inhalt oder höherem Format; ABook ist dann leer.</summary>
    class function Parse(const AJson: string; out ABook: TAtlasNoteBook): Boolean; static;
    class function ToJson(const ABook: TAtlasNoteBook): string; static;
    /// <summary>Format einer Datei (0 ohne oder bei ungültigem Inhalt).</summary>
    class function FormatOf(const AJson: string): Integer; static;
    /// <summary>Liest die Datei zu AProject über TAtlasDataFile.Load; False ohne, bei unbrauchbarer (dann als
    /// .defekt beiseitegelegt) oder gesperrter Datei (dann KeptFile). ABook ist dann leer mit Project = AProject.
    /// </summary>
    class function Load(const AFolder, AProject: string; out ABook: TAtlasNoteBook): Boolean; static;
    /// <summary>Ersetzt die Datei atomar; ohne Notizen wird sie gelöscht. False bei Fehler (einmal
    /// protokolliert), wenn die vorhandene Datei ein höheres Format hat, gerade nicht lesbar ist oder beim Laden
    /// gesperrt war (ABook.KeptFile).</summary>
    class function Save(const AFolder: string; const ABook: TAtlasNoteBook): Boolean; static;
    /// <summary>Alle lesbaren Notizbücher in AFolder (ohne geöffnetes Projekt), nach Projektpfad.</summary>
    class function LoadAll(const AFolder: string): TArray<TAtlasNoteBook>; static;
  end;

implementation

uses
  Winapi.Windows,
  System.Classes,
  System.IOUtils,
  System.JSON,
  System.Generics.Collections,
  System.Generics.Defaults,
  Atlas.Core.Projects.Summary,
  Atlas.Core.Files.DataFile,
  Atlas.Text.Json;

const
  // Bekannte Felder; alles andere bleibt beim Schreiben erhalten.
  cTopKeys: array[0..2] of string = ('format', 'project', 'notes');
  cNoteKeys: array[0..9] of string = ('id', 'file', 'line', 'text', 'lineText', 'before', 'after', 'created',
    'changed', 'orphaned');

{ TAtlasNote }

function TAtlasNote.Line: Integer;
begin
  Result := Anchor.Line;
end;

function TAtlasNote.Title: string;
var
  mLines: TArray<string>;
  mIndex, mFirst: Integer;
begin
  Result := '';
  mLines := TAtlasLineAnchors.Lines(Text);
  mFirst := -1;
  for mIndex := 0 to High(mLines) do
  begin
    if Trim(mLines[mIndex]) <> '' then
    begin
      mFirst := mIndex;
      Break;
    end;
  end;
  if mFirst < 0 then
  begin
    Exit;
  end;
  Result := Trim(mLines[mFirst]);
  for mIndex := mFirst + 1 to High(mLines) do
  begin
    if Trim(mLines[mIndex]) <> '' then
    begin
      Result := Result + ' …';
      Break;
    end;
  end;
end;

{ TAtlasNoteBook }

class function TAtlasNoteBook.Create(const AProject: string): TAtlasNoteBook;
begin
  Result := Default(TAtlasNoteBook);
  Result.Project := AProject;
end;

function TAtlasNoteBook.Count: Integer;
begin
  Result := Length(Notes);
end;

function TAtlasNoteBook.IndexOf(const AId: string): Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  for mIndex := 0 to High(Notes) do
  begin
    if SameText(Notes[mIndex].Id, AId) then
    begin
      Exit(mIndex);
    end;
  end;
end;

function TAtlasNoteBook.IndexAt(const AFileName: string; ALine: Integer): Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  for mIndex := 0 to High(Notes) do
  begin
    if not Notes[mIndex].Orphaned and (Notes[mIndex].Line = ALine) and
      TAtlasNotes.SameFile(Notes[mIndex].FileName, AFileName) then
    begin
      Exit(mIndex);
    end;
  end;
end;

function TAtlasNoteBook.AtLine(const AFileName: string; ALine: Integer): TArray<TAtlasNote>;
var
  mNote: TAtlasNote;
begin
  Result := nil;
  for mNote in Notes do
  begin
    if not mNote.Orphaned and (mNote.Line = ALine) and TAtlasNotes.SameFile(mNote.FileName, AFileName) then
    begin
      Result := Result + [mNote];
    end;
  end;
end;

function TAtlasNoteBook.ForFile(const AFileName: string): TArray<TAtlasNote>;
var
  mNote: TAtlasNote;
begin
  Result := nil;
  for mNote in Notes do
  begin
    if TAtlasNotes.SameFile(mNote.FileName, AFileName) then
    begin
      Result := Result + [mNote];
    end;
  end;
end;

function TAtlasNoteBook.Files: TArray<string>;
var
  mNote: TAtlasNote;
  mName: string;
  mKnown: Boolean;
begin
  Result := nil;
  for mNote in Notes do
  begin
    mKnown := False;
    for mName in Result do
    begin
      if TAtlasNotes.SameFile(mName, mNote.FileName) then
      begin
        mKnown := True;
        Break;
      end;
    end;
    if not mKnown then
    begin
      Result := Result + [mNote.FileName];
    end;
  end;
end;

function TAtlasNoteBook.OrphanCount: Integer;
var
  mNote: TAtlasNote;
begin
  Result := 0;
  for mNote in Notes do
  begin
    if mNote.Orphaned then
    begin
      Inc(Result);
    end;
  end;
end;

function TAtlasNoteBook.Add(const AFileName: string; const ALines: TArray<string>; ALine: Integer;
  const AText: string; ANowUtc: TDateTime): string;
var
  mNote: TAtlasNote;
begin
  mNote := Default(TAtlasNote);
  mNote.Id := TAtlasNotes.NewId;
  mNote.FileName := AFileName;
  mNote.Text := AText;
  mNote.Anchor := TAtlasLineAnchors.Capture(ALines, ALine);
  mNote.Created := ANowUtc;
  mNote.Changed := ANowUtc;
  Notes := Notes + [mNote];
  Result := mNote.Id;
end;

function TAtlasNoteBook.SetText(const AId, AText: string; ANowUtc: TDateTime): Boolean;
var
  mIndex: Integer;
begin
  mIndex := IndexOf(AId);
  Result := mIndex >= 0;
  if not Result then
  begin
    Exit;
  end;
  Notes[mIndex].Text := AText;
  Notes[mIndex].Changed := ANowUtc;
end;

function TAtlasNoteBook.Remove(const AId: string): Boolean;
var
  mIndex: Integer;
begin
  mIndex := IndexOf(AId);
  Result := mIndex >= 0;
  if Result then
  begin
    Delete(Notes, mIndex, 1);
  end;
end;

function TAtlasNoteBook.Relocate(const AFileName: string; const ALines: TArray<string>): Boolean;
var
  mIndex, mLine: Integer;
  mAnchor: TAtlasLineAnchor;
begin
  Result := False;
  for mIndex := 0 to High(Notes) do
  begin
    if not TAtlasNotes.SameFile(Notes[mIndex].FileName, AFileName) then
    begin
      Continue;
    end;
    if TAtlasLineAnchors.Locate(ALines, Notes[mIndex].Anchor, mLine) = TAtlasLineMatch.Orphaned then
    begin
      if not Notes[mIndex].Orphaned then
      begin
        Notes[mIndex].Orphaned := True;
        Result := True;
      end;
      Continue;
    end;
    // Gefunden: neuen Stand merken, damit die Notiz auch weiteren Änderungen folgt.
    mAnchor := TAtlasLineAnchors.Capture(ALines, mLine);
    if Notes[mIndex].Orphaned or not Notes[mIndex].Anchor.SameAs(mAnchor) then
    begin
      Notes[mIndex].Anchor := mAnchor;
      Notes[mIndex].Orphaned := False;
      Result := True;
    end;
  end;
end;

function TAtlasNoteBook.OrphanFile(const AFileName: string): Boolean;
var
  mIndex: Integer;
begin
  Result := False;
  for mIndex := 0 to High(Notes) do
  begin
    if TAtlasNotes.SameFile(Notes[mIndex].FileName, AFileName) and not Notes[mIndex].Orphaned then
    begin
      Notes[mIndex].Orphaned := True;
      Result := True;
    end;
  end;
end;

/// <summary>Dateiname ohne Ordner; unabhängig vom Trennzeichen des Systems.</summary>
function ShortName(const AFileName: string): string;
var
  mIndex: Integer;
begin
  Result := AFileName;
  for mIndex := Length(Result) downto 1 do
  begin
    if CharInSet(Result[mIndex], ['\', '/']) then
    begin
      Exit(Copy(Result, mIndex + 1, MaxInt));
    end;
  end;
end;

function CompareNotes(const A, B: TAtlasNote): Integer;
begin
  Result := CompareText(ShortName(A.FileName), ShortName(B.FileName));
  if Result = 0 then
  begin
    Result := CompareText(A.FileName, B.FileName);
  end;
  if Result = 0 then
  begin
    Result := A.Line - B.Line;
  end;
end;

function TAtlasNoteBook.Groups: TArray<TAtlasNoteGroup>;
var
  mSorted: TArray<TAtlasNote>;
  mNote: TAtlasNote;
  mGroup, mOrphans: TAtlasNoteGroup;
begin
  Result := nil;
  mSorted := Copy(Notes, 0, Length(Notes));
  TArray.Sort<TAtlasNote>(mSorted, TComparer<TAtlasNote>.Construct(
    function(const A, B: TAtlasNote): Integer
    begin
      Result := CompareNotes(A, B);
    end));
  mGroup := Default(TAtlasNoteGroup);
  mOrphans := Default(TAtlasNoteGroup);
  mOrphans.Orphaned := True;
  for mNote in mSorted do
  begin
    if mNote.Orphaned then
    begin
      mOrphans.Notes := mOrphans.Notes + [mNote];
      Continue;
    end;
    if (Length(mGroup.Notes) > 0) and not TAtlasNotes.SameFile(mGroup.FileName, mNote.FileName) then
    begin
      Result := Result + [mGroup];
      mGroup := Default(TAtlasNoteGroup);
    end;
    mGroup.FileName := mNote.FileName;
    mGroup.Notes := mGroup.Notes + [mNote];
  end;
  if Length(mGroup.Notes) > 0 then
  begin
    Result := Result + [mGroup];
  end;
  if Length(mOrphans.Notes) > 0 then
  begin
    Result := Result + [mOrphans];
  end;
end;

{ JSON-Helfer }

function Known(const AKeys: array of string; const AName: string): Boolean;
var
  mKey: string;
begin
  Result := False;
  for mKey in AKeys do
  begin
    if mKey = AName then
    begin
      Exit(True);
    end;
  end;
end;

function TextsOf(AObject: TJSONObject; const AName: string): TArray<string>;
var
  mValue: TJSONValue;
  mList: TJSONArray;
  mIndex: Integer;
begin
  Result := nil;
  if AObject = nil then
  begin
    Exit;
  end;
  mValue := AObject.GetValue(AName);
  if not (mValue is TJSONArray) then
  begin
    Exit;
  end;
  mList := TJSONArray(mValue);
  for mIndex := 0 to mList.Count - 1 do
  begin
    if (mList.Items[mIndex] is TJSONString) and (Length(Result) < TAtlasLineAnchors.cContextLines) then
    begin
      Result := Result + [TJSONString(mList.Items[mIndex]).Value];
    end;
  end;
end;

function TextsJson(const ATexts: TArray<string>): TJSONArray;
var
  mText: string;
begin
  Result := TJSONArray.Create;
  for mText in ATexts do
  begin
    Result.Add(mText);
  end;
end;

/// <summary>Unbekannte Felder aus AOriginal (darf nil sein) an ATarget anhängen.</summary>
procedure KeepUnknown(ATarget, AOriginal: TJSONObject; const AKeys: array of string);
var
  mIndex: Integer;
  mPair: TJSONPair;
begin
  if AOriginal = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to AOriginal.Count - 1 do
  begin
    mPair := AOriginal.Pairs[mIndex];
    if not Known(AKeys, mPair.JsonString.Value) then
    begin
      ATarget.AddPair(mPair.JsonString.Value, TJSONValue(mPair.JsonValue.Clone));
    end;
  end;
end;

/// <summary>Nur die unbekannten Felder einer Notiz als JSON-Objekt; '' ohne.</summary>
function ExtraOf(AObject: TJSONObject): string;
var
  mExtra: TJSONObject;
begin
  Result := '';
  mExtra := TJSONObject.Create;
  try
    KeepUnknown(mExtra, AObject, cNoteKeys);
    if mExtra.Count > 0 then
    begin
      Result := mExtra.ToJSON;
    end;
  finally
    mExtra.Free;
  end;
end;

function ParseObject(const AJson: string): TJSONObject;
var
  mValue: TJSONValue;
begin
  Result := nil;
  if AJson = '' then
  begin
    Exit;
  end;
  try
    mValue := TJSONObject.ParseJSONValue(AJson);
  except
    on Exception do
      mValue := nil;
  end;
  if mValue is TJSONObject then
  begin
    Result := TJSONObject(mValue);
  end
  else
  begin
    mValue.Free;
  end;
end;

function NoteOf(AObject: TJSONObject; out ANote: TAtlasNote): Boolean;
begin
  ANote := Default(TAtlasNote);
  ANote.Id := TJsonRead.Text(AObject, 'id');
  ANote.FileName := TJsonRead.Text(AObject, 'file');
  // Ohne Kennung oder Datei lässt sich die Notiz weder zeigen noch ändern.
  Result := (ANote.Id <> '') and (ANote.FileName <> '');
  if not Result then
  begin
    Exit;
  end;
  ANote.Text := TJsonRead.Text(AObject, 'text');
  ANote.Anchor.Line := TJsonRead.IntOr(AObject, 'line', 1) - 1;
  if ANote.Anchor.Line < 0 then
  begin
    ANote.Anchor.Line := 0;
  end;
  ANote.Anchor.Text := TJsonRead.Text(AObject, 'lineText');
  ANote.Anchor.Before := TextsOf(AObject, 'before');
  ANote.Anchor.After := TextsOf(AObject, 'after');
  ANote.Created := TAtlasProjectSummaries.TimeOf(TJsonRead.Text(AObject, 'created'));
  ANote.Changed := TAtlasProjectSummaries.TimeOf(TJsonRead.Text(AObject, 'changed'));
  ANote.Orphaned := TJsonRead.Flag(AObject, 'orphaned');
  ANote.Extra := ExtraOf(AObject);
end;

function NoteJson(const ANote: TAtlasNote): TJSONObject;
var
  mExtra: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('id', ANote.Id);
  Result.AddPair('file', ANote.FileName);
  Result.AddPair('line', TJSONNumber.Create(ANote.Line + 1));
  Result.AddPair('text', ANote.Text);
  Result.AddPair('lineText', ANote.Anchor.Text);
  Result.AddPair('before', TextsJson(ANote.Anchor.Before));
  Result.AddPair('after', TextsJson(ANote.Anchor.After));
  if ANote.Created > 0 then
  begin
    Result.AddPair('created', TAtlasProjectSummaries.TimeText(ANote.Created));
  end;
  if ANote.Changed > 0 then
  begin
    Result.AddPair('changed', TAtlasProjectSummaries.TimeText(ANote.Changed));
  end;
  if ANote.Orphaned then
  begin
    Result.AddPair('orphaned', TJSONBool.Create(True));
  end;
  mExtra := ParseObject(ANote.Extra);
  try
    KeepUnknown(Result, mExtra, cNoteKeys);
  finally
    mExtra.Free;
  end;
end;

{ TAtlasNotes }

class function TAtlasNotes.DefaultFolder: string;
var
  mBase: string;
begin
  Result := '';
  mBase := GetEnvironmentVariable('LOCALAPPDATA');
  if mBase <> '' then
  begin
    Result := IncludeTrailingPathDelimiter(IncludeTrailingPathDelimiter(mBase) + 'Atlas') + cFolderName;
  end;
end;

class function TAtlasNotes.FileFor(const AFolder, AProject: string): string;
begin
  Result := IncludeTrailingPathDelimiter(AFolder) + TAtlasProjectSummaries.KeyOf(AProject) + '.json';
end;

class function TAtlasNotes.SameFile(const A, B: string): Boolean;
begin
  Result := TAtlasProjectSummaries.NormalizedPath(A) = TAtlasProjectSummaries.NormalizedPath(B);
end;

class function TAtlasNotes.NewId: string;
var
  mGuid: TGUID;
begin
  if CreateGUID(mGuid) <> 0 then
  begin
    // Ohne GUID: Zeitpunkt und Zufall genügen für ein Notizbuch. Ohne Randomize wäre die Folge
    // bei jedem Start gleich.
    Randomize;
    Exit(LowerCase(IntToHex(Trunc(Now * 86400000), 12) + IntToHex(Random(MaxInt), 8)));
  end;
  Result := LowerCase(GUIDToString(mGuid));
  Result := Copy(Result, 2, Length(Result) - 2);
end;

class function TAtlasNotes.FormatOf(const AJson: string): Integer;
var
  mRoot: TJSONObject;
begin
  mRoot := ParseObject(AJson);
  try
    Result := TJsonRead.IntOr(mRoot, 'format', 0);
  finally
    mRoot.Free;
  end;
end;

class function TAtlasNotes.Parse(const AJson: string; out ABook: TAtlasNoteBook): Boolean;
var
  mRoot: TJSONObject;
  mValue: TJSONValue;
  mList: TJSONArray;
  mIndex: Integer;
  mNote: TAtlasNote;
begin
  ABook := TAtlasNoteBook.Create('');
  Result := False;
  mRoot := ParseObject(AJson);
  try
    if mRoot = nil then
    begin
      Exit;
    end;
    // Ohne "format" gilt 1; ein höheres Format kennt diese Fassung nicht.
    if TJsonRead.IntOr(mRoot, 'format', 1) > cFormat then
    begin
      Exit;
    end;
    ABook.Raw := AJson;
    ABook.Project := TJsonRead.Text(mRoot, 'project');
    mValue := mRoot.GetValue('notes');
    if mValue is TJSONArray then
    begin
      mList := TJSONArray(mValue);
      for mIndex := 0 to mList.Count - 1 do
      begin
        if (mList.Items[mIndex] is TJSONObject) and NoteOf(TJSONObject(mList.Items[mIndex]), mNote) then
        begin
          ABook.Notes := ABook.Notes + [mNote];
        end;
      end;
    end;
    Result := True;
  finally
    mRoot.Free;
  end;
end;

class function TAtlasNotes.ToJson(const ABook: TAtlasNoteBook): string;
var
  mOriginal, mRoot: TJSONObject;
  mList: TJSONArray;
  mNote: TAtlasNote;
begin
  mOriginal := ParseObject(ABook.Raw);
  mRoot := TJSONObject.Create;
  try
    mRoot.AddPair('format', TJSONNumber.Create(cFormat));
    mRoot.AddPair('project', ABook.Project);
    mList := TJSONArray.Create;
    mRoot.AddPair('notes', mList);
    for mNote in ABook.Notes do
    begin
      mList.AddElement(NoteJson(mNote));
    end;
    KeepUnknown(mRoot, mOriginal, cTopKeys);
    Result := mRoot.ToJSON;
  finally
    mRoot.Free;
    mOriginal.Free;
  end;
end;

class function TAtlasNotes.Load(const AFolder, AProject: string; out ABook: TAtlasNoteBook): Boolean;
var
  mFileName: string;
  mBook: TAtlasNoteBook;
  mParsed: Boolean;
  mLoad: TAtlasDataLoad;
begin
  ABook := TAtlasNoteBook.Create(AProject);
  Result := False;
  if (AFolder = '') or (Trim(AProject) = '') then
  begin
    Exit;
  end;
  mFileName := FileFor(AFolder, AProject);
  mParsed := False;
  mLoad := TAtlasDataFile.Load(mFileName, 'Notizen',
    function(const AText: string): Boolean
    begin
      mParsed := Parse(AText, mBook);
      // Ein höheres Format ist nicht unbrauchbar: nicht beiseitelegen; Save überschreibt es nicht.
      Result := mParsed or (FormatOf(AText) > cFormat);
    end);
  Result := mParsed and (mLoad = TAtlasDataLoad.Loaded);
  if Result then
  begin
    ABook := mBook;
    if ABook.Project = '' then
    begin
      ABook.Project := AProject;
    end;
  end
  else if not TAtlasDataFile.Writable(mLoad) then
  begin
    ABook.KeptFile := mFileName;
  end;
end;

class function TAtlasNotes.Save(const AFolder: string; const ABook: TAtlasNoteBook): Boolean;
var
  mFileName, mText: string;
begin
  Result := False;
  if (AFolder = '') or (Trim(ABook.Project) = '') then
  begin
    Exit;
  end;
  mFileName := FileFor(AFolder, ABook.Project);
  // Beim Laden gesperrt: Das Notizbuch kennt den Inhalt der Datei nicht.
  if SameFileName(mFileName, ABook.KeptFile) then
  begin
    Exit;
  end;
  try
    // Eine neuere Fassung hat die Datei geschrieben oder sie ist gerade nicht lesbar: nicht überschreiben.
    if FileExists(mFileName) and (not TAtlasDataFile.TryRead(mFileName, mText) or (FormatOf(mText) > cFormat)) then
    begin
      Exit;
    end;
    if ABook.Count = 0 then
    begin
      // Keine Notizen mehr: keine leere Datei liegen lassen.
      Result := not FileExists(mFileName) or System.SysUtils.DeleteFile(mFileName);
      Exit;
    end;
    // Atomar ersetzt, UTF-8 ohne BOM wie JSON üblich.
    TAtlasDataFile.Write(mFileName, ToJson(ABook));
    Result := True;
  except
    on E: Exception do
      TAtlasDataFile.ReportNotWritten('Notizen', E);
  end;
end;

class function TAtlasNotes.LoadAll(const AFolder: string): TArray<TAtlasNoteBook>;
var
  mSearch: TSearchRec;
  mBook: TAtlasNoteBook;
  mText: string;
begin
  Result := nil;
  if (AFolder = '') or not DirectoryExists(AFolder) then
  begin
    Exit;
  end;
  if FindFirst(IncludeTrailingPathDelimiter(AFolder) + '*.json', faAnyFile, mSearch) = 0 then
    try
      repeat
        // Gesperrt oder verschwunden: übergehen; nur lesen, beiseitegelegt wird beim Laden des Projekts.
        if ((mSearch.Attr and faDirectory) <> 0) or
          not TAtlasDataFile.TryRead(IncludeTrailingPathDelimiter(AFolder) + mSearch.Name, mText) then
        begin
          Continue;
        end;
        if Parse(mText, mBook) and (mBook.Project <> '') then
        begin
          Result := Result + [mBook];
        end;
      until FindNext(mSearch) <> 0;
    finally
      // Winapi.Windows hat ein gleichnamiges FindClose für Handles.
      System.SysUtils.FindClose(mSearch);
    end;
  TArray.Sort<TAtlasNoteBook>(Result, TComparer<TAtlasNoteBook>.Construct(
    function(const A, B: TAtlasNoteBook): Integer
    begin
      Result := CompareText(A.Project, B.Project);
    end));
end;

end.
