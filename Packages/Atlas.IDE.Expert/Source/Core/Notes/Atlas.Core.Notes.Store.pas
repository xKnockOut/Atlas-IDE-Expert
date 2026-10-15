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
    Format = 1;
    /// <summary>Unterordner von %LOCALAPPDATA%\Atlas.</summary>
    FolderName = 'Notes';
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
    /// <summary>Liest die Datei zu AProject; False ohne oder bei ungültiger Datei (ABook dann leer mit
    /// Project = AProject).</summary>
    class function Load(const AFolder, AProject: string; out ABook: TAtlasNoteBook): Boolean; static;
    /// <summary>Schreibt über eine temporäre Datei; ohne Notizen wird die Datei gelöscht. False bei Fehler
    /// oder wenn die vorhandene Datei ein höheres Format hat.</summary>
    class function Save(const AFolder: string; const ABook: TAtlasNoteBook): Boolean; static;
    /// <summary>Alle lesbaren Notizbücher in AFolder (ohne geöffnetes Projekt), nach Projektpfad.</summary>
    class function LoadAll(const AFolder: string): TArray<TAtlasNoteBook>; static;
  end;

implementation

uses
  System.Classes,
  System.IOUtils,
  System.JSON,
  System.Generics.Collections,
  System.Generics.Defaults,
  Atlas.Core.Projects.Summary;

const
  // Bekannte Felder; alles andere bleibt beim Schreiben erhalten.
  TopKeys: array[0..2] of string = ('format', 'project', 'notes');
  NoteKeys: array[0..9] of string = ('id', 'file', 'line', 'text', 'lineText', 'before', 'after', 'created',
    'changed', 'orphaned');

{ TAtlasNote }

function TAtlasNote.Line: Integer;
begin
  Result := Anchor.Line;
end;

function TAtlasNote.Title: string;
var
  Lines: TArray<string>;
  Index, First: Integer;
begin
  Result := '';
  Lines := TAtlasLineAnchors.Lines(Text);
  First := -1;
  for Index := 0 to High(Lines) do
    if Trim(Lines[Index]) <> '' then
    begin
      First := Index;
      Break;
    end;
  if First < 0 then
    Exit;
  Result := Trim(Lines[First]);
  for Index := First + 1 to High(Lines) do
    if Trim(Lines[Index]) <> '' then
    begin
      Result := Result + ' …';
      Break;
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
  Index: Integer;
begin
  Result := -1;
  for Index := 0 to High(Notes) do
    if SameText(Notes[Index].Id, AId) then
      Exit(Index);
end;

function TAtlasNoteBook.IndexAt(const AFileName: string; ALine: Integer): Integer;
var
  Index: Integer;
begin
  Result := -1;
  for Index := 0 to High(Notes) do
    if not Notes[Index].Orphaned and (Notes[Index].Line = ALine) and
      TAtlasNotes.SameFile(Notes[Index].FileName, AFileName) then
      Exit(Index);
end;

function TAtlasNoteBook.AtLine(const AFileName: string; ALine: Integer): TArray<TAtlasNote>;
var
  Note: TAtlasNote;
begin
  Result := nil;
  for Note in Notes do
    if not Note.Orphaned and (Note.Line = ALine) and TAtlasNotes.SameFile(Note.FileName, AFileName) then
      Result := Result + [Note];
end;

function TAtlasNoteBook.ForFile(const AFileName: string): TArray<TAtlasNote>;
var
  Note: TAtlasNote;
begin
  Result := nil;
  for Note in Notes do
    if TAtlasNotes.SameFile(Note.FileName, AFileName) then
      Result := Result + [Note];
end;

function TAtlasNoteBook.Files: TArray<string>;
var
  Note: TAtlasNote;
  Name: string;
  Known: Boolean;
begin
  Result := nil;
  for Note in Notes do
  begin
    Known := False;
    for Name in Result do
      if TAtlasNotes.SameFile(Name, Note.FileName) then
      begin
        Known := True;
        Break;
      end;
    if not Known then
      Result := Result + [Note.FileName];
  end;
end;

function TAtlasNoteBook.OrphanCount: Integer;
var
  Note: TAtlasNote;
begin
  Result := 0;
  for Note in Notes do
    if Note.Orphaned then
      Inc(Result);
end;

function TAtlasNoteBook.Add(const AFileName: string; const ALines: TArray<string>; ALine: Integer;
  const AText: string; ANowUtc: TDateTime): string;
var
  Note: TAtlasNote;
begin
  Note := Default(TAtlasNote);
  Note.Id := TAtlasNotes.NewId;
  Note.FileName := AFileName;
  Note.Text := AText;
  Note.Anchor := TAtlasLineAnchors.Capture(ALines, ALine);
  Note.Created := ANowUtc;
  Note.Changed := ANowUtc;
  Notes := Notes + [Note];
  Result := Note.Id;
end;

function TAtlasNoteBook.SetText(const AId, AText: string; ANowUtc: TDateTime): Boolean;
var
  Index: Integer;
begin
  Index := IndexOf(AId);
  Result := Index >= 0;
  if not Result then
    Exit;
  Notes[Index].Text := AText;
  Notes[Index].Changed := ANowUtc;
end;

function TAtlasNoteBook.Remove(const AId: string): Boolean;
var
  Index: Integer;
begin
  Index := IndexOf(AId);
  Result := Index >= 0;
  if Result then
    Delete(Notes, Index, 1);
end;

function TAtlasNoteBook.Relocate(const AFileName: string; const ALines: TArray<string>): Boolean;
var
  Index, Line: Integer;
  Anchor: TAtlasLineAnchor;
begin
  Result := False;
  for Index := 0 to High(Notes) do
  begin
    if not TAtlasNotes.SameFile(Notes[Index].FileName, AFileName) then
      Continue;
    if TAtlasLineAnchors.Locate(ALines, Notes[Index].Anchor, Line) = TAtlasLineMatch.Orphaned then
    begin
      if not Notes[Index].Orphaned then
      begin
        Notes[Index].Orphaned := True;
        Result := True;
      end;
      Continue;
    end;
    // Gefunden: neuen Stand merken, damit die Notiz auch weiteren Änderungen folgt.
    Anchor := TAtlasLineAnchors.Capture(ALines, Line);
    if Notes[Index].Orphaned or not Notes[Index].Anchor.SameAs(Anchor) then
    begin
      Notes[Index].Anchor := Anchor;
      Notes[Index].Orphaned := False;
      Result := True;
    end;
  end;
end;

function TAtlasNoteBook.OrphanFile(const AFileName: string): Boolean;
var
  Index: Integer;
begin
  Result := False;
  for Index := 0 to High(Notes) do
    if TAtlasNotes.SameFile(Notes[Index].FileName, AFileName) and not Notes[Index].Orphaned then
    begin
      Notes[Index].Orphaned := True;
      Result := True;
    end;
end;

/// <summary>Dateiname ohne Ordner; unabhängig vom Trennzeichen des Systems.</summary>
function ShortName(const AFileName: string): string;
var
  Index: Integer;
begin
  Result := AFileName;
  for Index := Length(Result) downto 1 do
    if CharInSet(Result[Index], ['\', '/']) then
      Exit(Copy(Result, Index + 1, MaxInt));
end;

function CompareNotes(const A, B: TAtlasNote): Integer;
begin
  Result := CompareText(ShortName(A.FileName), ShortName(B.FileName));
  if Result = 0 then
    Result := CompareText(A.FileName, B.FileName);
  if Result = 0 then
    Result := A.Line - B.Line;
end;

function TAtlasNoteBook.Groups: TArray<TAtlasNoteGroup>;
var
  Sorted: TArray<TAtlasNote>;
  Note: TAtlasNote;
  Group, Orphans: TAtlasNoteGroup;
begin
  Result := nil;
  Sorted := Copy(Notes, 0, Length(Notes));
  TArray.Sort<TAtlasNote>(Sorted, TComparer<TAtlasNote>.Construct(
    function(const A, B: TAtlasNote): Integer
    begin
      Result := CompareNotes(A, B);
    end));
  Group := Default(TAtlasNoteGroup);
  Orphans := Default(TAtlasNoteGroup);
  Orphans.Orphaned := True;
  for Note in Sorted do
  begin
    if Note.Orphaned then
    begin
      Orphans.Notes := Orphans.Notes + [Note];
      Continue;
    end;
    if (Length(Group.Notes) > 0) and not TAtlasNotes.SameFile(Group.FileName, Note.FileName) then
    begin
      Result := Result + [Group];
      Group := Default(TAtlasNoteGroup);
    end;
    Group.FileName := Note.FileName;
    Group.Notes := Group.Notes + [Note];
  end;
  if Length(Group.Notes) > 0 then
    Result := Result + [Group];
  if Length(Orphans.Notes) > 0 then
    Result := Result + [Orphans];
end;

{ JSON-Helfer }

function Known(const AKeys: array of string; const AName: string): Boolean;
var
  Key: string;
begin
  Result := False;
  for Key in AKeys do
    if Key = AName then
      Exit(True);
end;

function TextOf(AObject: TJSONObject; const AName: string): string;
var
  Value: TJSONValue;
begin
  Result := '';
  if AObject = nil then
    Exit;
  Value := AObject.GetValue(AName);
  if Value is TJSONString then
    Result := TJSONString(Value).Value;
end;

function NumberOf(AObject: TJSONObject; const AName: string; ADefault: Integer): Integer;
var
  Value: TJSONValue;
begin
  Result := ADefault;
  if AObject = nil then
    Exit;
  Value := AObject.GetValue(AName);
  if Value is TJSONNumber then
    Result := TJSONNumber(Value).AsInt
  else if Value is TJSONString then
    Result := StrToIntDef(TJSONString(Value).Value, ADefault);
end;

function FlagOf(AObject: TJSONObject; const AName: string): Boolean;
var
  Value: TJSONValue;
begin
  Result := False;
  if AObject = nil then
    Exit;
  Value := AObject.GetValue(AName);
  if Value is TJSONBool then
    Result := SameText(Value.Value, 'true');
end;

function TextsOf(AObject: TJSONObject; const AName: string): TArray<string>;
var
  Value: TJSONValue;
  List: TJSONArray;
  Index: Integer;
begin
  Result := nil;
  if AObject = nil then
    Exit;
  Value := AObject.GetValue(AName);
  if not (Value is TJSONArray) then
    Exit;
  List := TJSONArray(Value);
  for Index := 0 to List.Count - 1 do
    if (List.Items[Index] is TJSONString) and (Length(Result) < TAtlasLineAnchors.ContextLines) then
      Result := Result + [TJSONString(List.Items[Index]).Value];
end;

function TextsJson(const ATexts: TArray<string>): TJSONArray;
var
  Text: string;
begin
  Result := TJSONArray.Create;
  for Text in ATexts do
    Result.Add(Text);
end;

/// <summary>Unbekannte Felder aus AOriginal (darf nil sein) an ATarget anhängen.</summary>
procedure KeepUnknown(ATarget, AOriginal: TJSONObject; const AKeys: array of string);
var
  Index: Integer;
  Pair: TJSONPair;
begin
  if AOriginal = nil then
    Exit;
  for Index := 0 to AOriginal.Count - 1 do
  begin
    Pair := AOriginal.Pairs[Index];
    if not Known(AKeys, Pair.JsonString.Value) then
      ATarget.AddPair(Pair.JsonString.Value, TJSONValue(Pair.JsonValue.Clone));
  end;
end;

/// <summary>Nur die unbekannten Felder einer Notiz als JSON-Objekt; '' ohne.</summary>
function ExtraOf(AObject: TJSONObject): string;
var
  Extra: TJSONObject;
begin
  Result := '';
  Extra := TJSONObject.Create;
  try
    KeepUnknown(Extra, AObject, NoteKeys);
    if Extra.Count > 0 then
      Result := Extra.ToJSON;
  finally
    Extra.Free;
  end;
end;

function ParseObject(const AJson: string): TJSONObject;
var
  Value: TJSONValue;
begin
  Result := nil;
  if AJson = '' then
    Exit;
  Value := nil;
  try
    Value := TJSONObject.ParseJSONValue(AJson);
  except
    on Exception do
      Value := nil;
  end;
  if Value is TJSONObject then
    Result := TJSONObject(Value)
  else
    Value.Free;
end;

function NoteOf(AObject: TJSONObject; out ANote: TAtlasNote): Boolean;
begin
  ANote := Default(TAtlasNote);
  ANote.Id := TextOf(AObject, 'id');
  ANote.FileName := TextOf(AObject, 'file');
  // Ohne Kennung oder Datei lässt sich die Notiz weder zeigen noch ändern.
  Result := (ANote.Id <> '') and (ANote.FileName <> '');
  if not Result then
    Exit;
  ANote.Text := TextOf(AObject, 'text');
  ANote.Anchor.Line := NumberOf(AObject, 'line', 1) - 1;
  if ANote.Anchor.Line < 0 then
    ANote.Anchor.Line := 0;
  ANote.Anchor.Text := TextOf(AObject, 'lineText');
  ANote.Anchor.Before := TextsOf(AObject, 'before');
  ANote.Anchor.After := TextsOf(AObject, 'after');
  ANote.Created := TAtlasProjectSummaries.TimeOf(TextOf(AObject, 'created'));
  ANote.Changed := TAtlasProjectSummaries.TimeOf(TextOf(AObject, 'changed'));
  ANote.Orphaned := FlagOf(AObject, 'orphaned');
  ANote.Extra := ExtraOf(AObject);
end;

function NoteJson(const ANote: TAtlasNote): TJSONObject;
var
  Extra: TJSONObject;
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
    Result.AddPair('created', TAtlasProjectSummaries.TimeText(ANote.Created));
  if ANote.Changed > 0 then
    Result.AddPair('changed', TAtlasProjectSummaries.TimeText(ANote.Changed));
  if ANote.Orphaned then
    Result.AddPair('orphaned', TJSONBool.Create(True));
  Extra := ParseObject(ANote.Extra);
  try
    KeepUnknown(Result, Extra, NoteKeys);
  finally
    Extra.Free;
  end;
end;

function ReadText(const AFileName: string): string;
var
  Bytes: TBytes;
begin
  Bytes := TFile.ReadAllBytes(AFileName);
  // Mit oder ohne BOM.
  if (Length(Bytes) >= 3) and (Bytes[0] = $EF) and (Bytes[1] = $BB) and (Bytes[2] = $BF) then
    Result := TEncoding.UTF8.GetString(Bytes, 3, Length(Bytes) - 3)
  else
    Result := TEncoding.UTF8.GetString(Bytes);
end;

{ TAtlasNotes }

class function TAtlasNotes.DefaultFolder: string;
var
  Base: string;
begin
  Result := '';
  Base := GetEnvironmentVariable('LOCALAPPDATA');
  if Base <> '' then
    Result := IncludeTrailingPathDelimiter(IncludeTrailingPathDelimiter(Base) + 'Atlas') + FolderName;
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
  Guid: TGUID;
begin
  if CreateGUID(Guid) <> 0 then
    // Ohne GUID: Zeitpunkt und Zufall genügen für ein Notizbuch.
    Exit(LowerCase(IntToHex(Trunc(Now * 86400000), 12) + IntToHex(Random(MaxInt), 8)));
  Result := LowerCase(GUIDToString(Guid));
  Result := Copy(Result, 2, Length(Result) - 2);
end;

class function TAtlasNotes.FormatOf(const AJson: string): Integer;
var
  Root: TJSONObject;
begin
  Root := ParseObject(AJson);
  try
    Result := NumberOf(Root, 'format', 0);
  finally
    Root.Free;
  end;
end;

class function TAtlasNotes.Parse(const AJson: string; out ABook: TAtlasNoteBook): Boolean;
var
  Root: TJSONObject;
  Value: TJSONValue;
  List: TJSONArray;
  Index: Integer;
  Note: TAtlasNote;
begin
  ABook := TAtlasNoteBook.Create('');
  Result := False;
  Root := ParseObject(AJson);
  try
    if Root = nil then
      Exit;
    // Ohne "format" gilt 1; ein höheres Format kennt diese Fassung nicht.
    if NumberOf(Root, 'format', 1) > Format then
      Exit;
    ABook.Raw := AJson;
    ABook.Project := TextOf(Root, 'project');
    Value := Root.GetValue('notes');
    if Value is TJSONArray then
    begin
      List := TJSONArray(Value);
      for Index := 0 to List.Count - 1 do
        if (List.Items[Index] is TJSONObject) and NoteOf(TJSONObject(List.Items[Index]), Note) then
          ABook.Notes := ABook.Notes + [Note];
    end;
    Result := True;
  finally
    Root.Free;
  end;
end;

class function TAtlasNotes.ToJson(const ABook: TAtlasNoteBook): string;
var
  Original, Root: TJSONObject;
  List: TJSONArray;
  Note: TAtlasNote;
begin
  Original := ParseObject(ABook.Raw);
  Root := TJSONObject.Create;
  try
    Root.AddPair('format', TJSONNumber.Create(Format));
    Root.AddPair('project', ABook.Project);
    List := TJSONArray.Create;
    Root.AddPair('notes', List);
    for Note in ABook.Notes do
      List.AddElement(NoteJson(Note));
    KeepUnknown(Root, Original, TopKeys);
    Result := Root.ToJSON;
  finally
    Root.Free;
    Original.Free;
  end;
end;

class function TAtlasNotes.Load(const AFolder, AProject: string; out ABook: TAtlasNoteBook): Boolean;
var
  FileName, Text: string;
begin
  ABook := TAtlasNoteBook.Create(AProject);
  Result := False;
  if (AFolder = '') or (Trim(AProject) = '') then
    Exit;
  FileName := FileFor(AFolder, AProject);
  if not FileExists(FileName) then
    Exit;
  try
    Text := ReadText(FileName);
  except
    // Gesperrt oder unlesbar: wie ohne Datei.
    on Exception do
      Exit;
  end;
  Result := Parse(Text, ABook);
  if not Result then
    ABook := TAtlasNoteBook.Create(AProject)
  else if ABook.Project = '' then
    ABook.Project := AProject;
end;

class function TAtlasNotes.Save(const AFolder: string; const ABook: TAtlasNoteBook): Boolean;
var
  FileName, Temp: string;
begin
  Result := False;
  if (AFolder = '') or (Trim(ABook.Project) = '') then
    Exit;
  FileName := FileFor(AFolder, ABook.Project);
  try
    // Eine neuere Fassung hat die Datei geschrieben: nicht überschreiben.
    if FileExists(FileName) and (FormatOf(ReadText(FileName)) > Format) then
      Exit;
    if ABook.Count = 0 then
    begin
      // Keine Notizen mehr: keine leere Datei liegen lassen.
      Result := not FileExists(FileName) or System.SysUtils.DeleteFile(FileName);
      Exit;
    end;
    ForceDirectories(AFolder);
    Temp := FileName + '.tmp';
    // Ohne BOM: UTF-8 wie JSON üblich.
    TFile.WriteAllBytes(Temp, TEncoding.UTF8.GetBytes(ToJson(ABook)));
    if FileExists(FileName) then
      System.SysUtils.DeleteFile(FileName);
    Result := RenameFile(Temp, FileName);
  except
    on Exception do
      Result := False;
  end;
end;

class function TAtlasNotes.LoadAll(const AFolder: string): TArray<TAtlasNoteBook>;
var
  Search: TSearchRec;
  Book: TAtlasNoteBook;
  Text: string;
begin
  Result := nil;
  if (AFolder = '') or not DirectoryExists(AFolder) then
    Exit;
  if FindFirst(IncludeTrailingPathDelimiter(AFolder) + '*.json', faAnyFile, Search) = 0 then
    try
      repeat
        if (Search.Attr and faDirectory) <> 0 then
          Continue;
        try
          Text := ReadText(IncludeTrailingPathDelimiter(AFolder) + Search.Name);
        except
          on Exception do
            Continue;
        end;
        if Parse(Text, Book) and (Book.Project <> '') then
          Result := Result + [Book];
      until FindNext(Search) <> 0;
    finally
      FindClose(Search);
    end;
  TArray.Sort<TAtlasNoteBook>(Result, TComparer<TAtlasNoteBook>.Construct(
    function(const A, B: TAtlasNoteBook): Integer
    begin
      Result := CompareText(A.Project, B.Project);
    end));
end;

end.
