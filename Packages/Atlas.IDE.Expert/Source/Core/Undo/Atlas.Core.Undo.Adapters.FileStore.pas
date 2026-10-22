unit Atlas.Core.Undo.Adapters.FileStore;

// Sicherung der Atlas-Änderungssätze (#721, undo.multiFile.persist) in einem
// Ordner, in der IDE %LOCALAPPDATA%\Atlas\undo: je Satz eine Datei
// set-<Kennung>.json mit Aktion, Zeit und je Datei Art, Projekt, Zustand und
// den Inhalten vorher und nachher samt Kodierung. Geschrieben wird erst in
// eine Nachbardatei, die dann die alte atomar ersetzt (TAtlasTextFile.Replace;
// früher Löschen und Umbenennen, Bericht N3). Ein unlesbarer Satz wird beim
// Laden übergangen und nicht als .defekt beiseitegelegt: Er ließe sich ohnehin
// nicht anwenden, und Shrink räumt ihn mit den ältesten weg. Nach jedem
// Sichern fallen die ältesten Sätze weg, bis alle zusammen höchstens
// MaxBytes groß sind; ein einzelner Satz über der Grenze wird gar nicht
// gesichert. Die Dateien liegen
// nur im Profil des Benutzers und nie in einem Protokoll (#647).

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Core.Files.TextFile,
  Atlas.Core.Undo.Contract;

type
  TAtlasUndoFileStore = class(TInterfacedObject, IAtlasUndoStore)
  private
    FFolder: string;
    FMaxBytes: Int64;
    function FileOf(AId: Integer): string;
    function SetFiles: TArray<string>;
    procedure Shrink;
  public
    constructor Create(const AFolder: string; AMaxBytes: Int64);
    procedure Save(const ASet: TAtlasChangeSet);
    procedure Delete(AId: Integer);
    function Load: TArray<TAtlasChangeSet>;
    procedure Clear;
    /// <summary>Satz als JSON; die Gegenrichtung liefert False für ungültige Daten.</summary>
    class function ToJson(const ASet: TAtlasChangeSet): TJSONObject; static;
    class function FromJson(const AValue: TJSONValue; out ASet: TAtlasChangeSet): Boolean; static;
    property Folder: string read FFolder;
    property MaxBytes: Int64 read FMaxBytes write FMaxBytes;
  end;

implementation

uses
  System.Classes,
  System.IOUtils,
  System.DateUtils,
  System.Generics.Collections,
  System.Generics.Defaults;

const
  Prefix = 'set-';
  Extension = '.json';
  EncodingNames: array[TAtlasTextEncoding] of string = ('utf8bom', 'utf8', 'utf16le', 'utf16be', 'ansi');
  KindNames: array[TAtlasFileChangeKind] of string = ('modified', 'created', 'deleted');

function ContentToJson(const AContent: TAtlasTextFileContent): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('text', AContent.Text);
  Result.AddPair('encoding', EncodingNames[AContent.Encoding]);
  Result.AddPair('codePage', TJSONNumber.Create(AContent.CodePage));
end;

function ContentFromJson(const AValue: TJSONValue; out AContent: TAtlasTextFileContent): Boolean;
var
  Name: string;
  Encoding: TAtlasTextEncoding;
begin
  AContent := Default(TAtlasTextFileContent);
  AContent.Encoding := TAtlasTextEncoding.Utf8Bom;
  Result := (AValue is TJSONObject) and TJSONObject(AValue).TryGetValue<string>('text', AContent.Text) and
    TJSONObject(AValue).TryGetValue<string>('encoding', Name) and
    TJSONObject(AValue).TryGetValue<Integer>('codePage', AContent.CodePage);
  if not Result then
    Exit;
  for Encoding := Low(TAtlasTextEncoding) to High(TAtlasTextEncoding) do
    if EncodingNames[Encoding] = Name then
    begin
      AContent.Encoding := Encoding;
      Exit(True);
    end;
  Result := False;
end;

{ TAtlasUndoFileStore }

constructor TAtlasUndoFileStore.Create(const AFolder: string; AMaxBytes: Int64);
begin
  inherited Create;
  FFolder := AFolder;
  FMaxBytes := AMaxBytes;
end;

function TAtlasUndoFileStore.FileOf(AId: Integer): string;
begin
  Result := TPath.Combine(FFolder, Format('%s%.6d%s', [Prefix, AId, Extension]));
end;

function TAtlasUndoFileStore.SetFiles: TArray<string>;
begin
  Result := nil;
  if not TDirectory.Exists(FFolder) then
    Exit;
  Result := TDirectory.GetFiles(FFolder, Prefix + '*' + Extension);
  // Kennungen mit führenden Nullen: alphabetisch = älteste zuerst.
  TArray.Sort<string>(Result, TComparer<string>.Construct(
    function(const A, B: string): Integer
    begin
      Result := CompareText(ExtractFileName(A), ExtractFileName(B));
    end));
end;

class function TAtlasUndoFileStore.ToJson(const ASet: TAtlasChangeSet): TJSONObject;
var
  Files: TJSONArray;
  Item: TJSONObject;
  Change: TAtlasFileChange;
begin
  Result := TJSONObject.Create;
  Result.AddPair('id', TJSONNumber.Create(ASet.Id));
  Result.AddPair('action', ASet.Action);
  Result.AddPair('time', DateToISO8601(ASet.Time, False));
  Files := TJSONArray.Create;
  Result.AddPair('files', Files);
  for Change in ASet.Files do
  begin
    Item := TJSONObject.Create;
    Files.AddElement(Item);
    Item.AddPair('file', Change.FileName);
    Item.AddPair('kind', KindNames[Change.Kind]);
    Item.AddPair('project', Change.Project);
    Item.AddPair('undone', TJSONBool.Create(Change.Undone));
    if Change.Kind <> TAtlasFileChangeKind.Created then
      Item.AddPair('before', ContentToJson(Change.Before));
    if Change.Kind <> TAtlasFileChangeKind.Deleted then
      Item.AddPair('after', ContentToJson(Change.After));
  end;
end;

class function TAtlasUndoFileStore.FromJson(const AValue: TJSONValue; out ASet: TAtlasChangeSet): Boolean;
var
  Root, Item: TJSONObject;
  Files: TJSONArray;
  Value: TJSONValue;
  Change: TAtlasFileChange;
  Time, Kind: string;
  Known: Boolean;
  Candidate: TAtlasFileChangeKind;
begin
  ASet := Default(TAtlasChangeSet);
  if not (AValue is TJSONObject) then
    Exit(False);
  Root := TJSONObject(AValue);
  if not (Root.TryGetValue<Integer>('id', ASet.Id) and Root.TryGetValue<string>('action', ASet.Action) and
    Root.TryGetValue<string>('time', Time) and Root.TryGetValue<TJSONArray>('files', Files)) then
    Exit(False);
  if not TryISO8601ToDate(Time, ASet.Time, False) then
    Exit(False);
  for Value in Files do
  begin
    if not (Value is TJSONObject) then
      Exit(False);
    Item := TJSONObject(Value);
    Change := Default(TAtlasFileChange);
    if not (Item.TryGetValue<string>('file', Change.FileName) and Item.TryGetValue<string>('kind', Kind) and
      Item.TryGetValue<string>('project', Change.Project) and Item.TryGetValue<Boolean>('undone', Change.Undone)) then
      Exit(False);
    Known := False;
    for Candidate := Low(TAtlasFileChangeKind) to High(TAtlasFileChangeKind) do
      if KindNames[Candidate] = Kind then
      begin
        Change.Kind := Candidate;
        Known := True;
      end;
    if not Known then
      Exit(False);
    if (Change.Kind <> TAtlasFileChangeKind.Created) and not ContentFromJson(Item.GetValue('before'),
      Change.Before) then
      Exit(False);
    if (Change.Kind <> TAtlasFileChangeKind.Deleted) and not ContentFromJson(Item.GetValue('after'),
      Change.After) then
      Exit(False);
    ASet.Files := ASet.Files + [Change];
  end;
  Result := (ASet.Id > 0) and (Length(ASet.Files) > 0);
end;

procedure TAtlasUndoFileStore.Save(const ASet: TAtlasChangeSet);
var
  Json: TJSONObject;
  Bytes: TBytes;
  FileName: string;
begin
  Json := ToJson(ASet);
  try
    Bytes := TEncoding.UTF8.GetBytes(Json.ToJSON);
  finally
    Json.Free;
  end;
  FileName := FileOf(ASet.Id);
  if Length(Bytes) > FMaxBytes then
  begin
    // Zu groß für die Grenze: nicht sichern, auch keinen älteren Stand dieses Satzes behalten.
    if TFile.Exists(FileName) then
      TFile.Delete(FileName);
    Exit;
  end;
  TDirectory.CreateDirectory(FFolder);
  TAtlasTextFile.Replace(FileName, Bytes);
  Shrink;
end;

procedure TAtlasUndoFileStore.Shrink;
var
  Files: TArray<string>;
  Total: Int64;
  Index: Integer;
begin
  Files := SetFiles;
  Total := 0;
  for Index := 0 to High(Files) do
    Inc(Total, TFile.GetSize(Files[Index]));
  Index := 0;
  while (Total > FMaxBytes) and (Index < Length(Files)) do
  begin
    Dec(Total, TFile.GetSize(Files[Index]));
    TFile.Delete(Files[Index]);
    Inc(Index);
  end;
end;

procedure TAtlasUndoFileStore.Delete(AId: Integer);
begin
  if TFile.Exists(FileOf(AId)) then
    TFile.Delete(FileOf(AId));
end;

function TAtlasUndoFileStore.Load: TArray<TAtlasChangeSet>;
var
  FileName: string;
  Value: TJSONValue;
  ChangeSet: TAtlasChangeSet;
begin
  Result := nil;
  for FileName in SetFiles do
  begin
    // Nicht lesbare oder kaputte Datei: überspringen (siehe Kopf). Lesen teilt Löschen (Bericht M5).
    try
      Value := TJSONObject.ParseJSONValue(TEncoding.UTF8.GetString(TAtlasTextFile.ReadAllBytes(FileName)));
    except
      on EStreamError do
        Value := nil;
    end;
    try
      if FromJson(Value, ChangeSet) then
        Result := Result + [ChangeSet];
    finally
      Value.Free;
    end;
  end;
end;

procedure TAtlasUndoFileStore.Clear;
var
  FileName: string;
begin
  for FileName in SetFiles do
    TFile.Delete(FileName);
end;

end.
