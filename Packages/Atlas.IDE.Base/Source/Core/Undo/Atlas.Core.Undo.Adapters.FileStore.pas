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
  cPrefix = 'set-';
  cExtension = '.json';
  cEncodingNames: array[TAtlasTextEncoding] of string = ('utf8bom', 'utf8', 'utf16le', 'utf16be', 'ansi');
  cKindNames: array[TAtlasFileChangeKind] of string = ('modified', 'created', 'deleted');

function ContentToJson(const AContent: TAtlasTextFileContent): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('text', AContent.Text);
  Result.AddPair('encoding', cEncodingNames[AContent.Encoding]);
  Result.AddPair('codePage', TJSONNumber.Create(AContent.CodePage));
end;

function ContentFromJson(const AValue: TJSONValue; out AContent: TAtlasTextFileContent): Boolean;
var
  mName: string;
  mEncoding: TAtlasTextEncoding;
begin
  AContent := Default(TAtlasTextFileContent);
  AContent.Encoding := TAtlasTextEncoding.Utf8Bom;
  Result := (AValue is TJSONObject) and TJSONObject(AValue).TryGetValue<string>('text', AContent.Text) and
    TJSONObject(AValue).TryGetValue<string>('encoding', mName) and
    TJSONObject(AValue).TryGetValue<Integer>('codePage', AContent.CodePage);
  if not Result then
  begin
    Exit;
  end;
  for mEncoding := Low(TAtlasTextEncoding) to High(TAtlasTextEncoding) do
  begin
    if cEncodingNames[mEncoding] = mName then
    begin
      AContent.Encoding := mEncoding;
      Exit(True);
    end;
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
  Result := TPath.Combine(FFolder, Format('%s%.6d%s', [cPrefix, AId, cExtension]));
end;

function TAtlasUndoFileStore.SetFiles: TArray<string>;
begin
  Result := nil;
  if not TDirectory.Exists(FFolder) then
  begin
    Exit;
  end;
  Result := TDirectory.GetFiles(FFolder, cPrefix + '*' + cExtension);
  // Kennungen mit führenden Nullen: alphabetisch = älteste zuerst.
  TArray.Sort<string>(Result, TComparer<string>.Construct(
    function(const A, B: string): Integer
    begin
      Result := CompareText(ExtractFileName(A), ExtractFileName(B));
    end));
end;

class function TAtlasUndoFileStore.ToJson(const ASet: TAtlasChangeSet): TJSONObject;
var
  mFiles: TJSONArray;
  mItem: TJSONObject;
  mChange: TAtlasFileChange;
begin
  Result := TJSONObject.Create;
  Result.AddPair('id', TJSONNumber.Create(ASet.Id));
  Result.AddPair('action', ASet.Action);
  Result.AddPair('time', DateToISO8601(ASet.Time, False));
  mFiles := TJSONArray.Create;
  Result.AddPair('files', mFiles);
  for mChange in ASet.Files do
  begin
    mItem := TJSONObject.Create;
    mFiles.AddElement(mItem);
    mItem.AddPair('file', mChange.FileName);
    mItem.AddPair('kind', cKindNames[mChange.Kind]);
    mItem.AddPair('project', mChange.Project);
    mItem.AddPair('undone', TJSONBool.Create(mChange.Undone));
    if mChange.Kind <> TAtlasFileChangeKind.Created then
    begin
      mItem.AddPair('before', ContentToJson(mChange.Before));
    end;
    if mChange.Kind <> TAtlasFileChangeKind.Deleted then
    begin
      mItem.AddPair('after', ContentToJson(mChange.After));
    end;
  end;
end;

/// <summary>Kennung, Aktion, Zeit und die Liste der Dateien; False, wenn etwas fehlt.</summary>
function HeaderFromJson(const AValue: TJSONValue; var ASet: TAtlasChangeSet; out AFiles: TJSONArray): Boolean;
var
  mRoot: TJSONObject;
  mTime: string;
begin
  AFiles := nil;
  Result := AValue is TJSONObject;
  if Result then
  begin
    mRoot := TJSONObject(AValue);
    Result := mRoot.TryGetValue<Integer>('id', ASet.Id) and mRoot.TryGetValue<string>('action', ASet.Action) and
      mRoot.TryGetValue<string>('time', mTime) and mRoot.TryGetValue<TJSONArray>('files', AFiles) and
      TryISO8601ToDate(mTime, ASet.Time, False);
  end;
end;

function KindOf(const AName: string; out AKind: TAtlasFileChangeKind): Boolean;
var
  mCandidate: TAtlasFileChangeKind;
begin
  Result := False;
  AKind := Low(TAtlasFileChangeKind);
  for mCandidate := Low(TAtlasFileChangeKind) to High(TAtlasFileChangeKind) do
  begin
    if cKindNames[mCandidate] = AName then
    begin
      AKind := mCandidate;
      Result := True;
    end;
  end;
end;

/// <summary>Eine Datei der Änderung; vorher fehlt bei neuen, nachher bei gelöschten Dateien.</summary>
function ChangeFromJson(const AValue: TJSONValue; out AChange: TAtlasFileChange): Boolean;
var
  mItem: TJSONObject;
  mKind: string;
begin
  AChange := Default(TAtlasFileChange);
  Result := AValue is TJSONObject;
  if not Result then
  begin
    Exit;
  end;
  mItem := TJSONObject(AValue);
  Result := mItem.TryGetValue<string>('file', AChange.FileName) and mItem.TryGetValue<string>('kind', mKind) and
    mItem.TryGetValue<string>('project', AChange.Project) and mItem.TryGetValue<Boolean>('undone', AChange.Undone) and
    KindOf(mKind, AChange.Kind);
  if Result and (AChange.Kind <> TAtlasFileChangeKind.Created) then
  begin
    Result := ContentFromJson(mItem.GetValue('before'), AChange.Before);
  end;
  if Result and (AChange.Kind <> TAtlasFileChangeKind.Deleted) then
  begin
    Result := ContentFromJson(mItem.GetValue('after'), AChange.After);
  end;
end;
class function TAtlasUndoFileStore.FromJson(const AValue: TJSONValue; out ASet: TAtlasChangeSet): Boolean;
var
  mFiles: TJSONArray;
  mValue: TJSONValue;
  mChange: TAtlasFileChange;
begin
  ASet := Default(TAtlasChangeSet);
  Result := HeaderFromJson(AValue, ASet, mFiles);
  if not Result then
  begin
    Exit;
  end;
  for mValue in mFiles do
  begin
    Result := ChangeFromJson(mValue, mChange);
    if not Result then
    begin
      Exit;
    end;
    ASet.Files := ASet.Files + [mChange];
  end;
  Result := (ASet.Id > 0) and (Length(ASet.Files) > 0);
end;

procedure TAtlasUndoFileStore.Save(const ASet: TAtlasChangeSet);
var
  mJson: TJSONObject;
  mBytes: TBytes;
  mFileName: string;
begin
  mJson := ToJson(ASet);
  try
    mBytes := TEncoding.UTF8.GetBytes(mJson.ToJSON);
  finally
    mJson.Free;
  end;
  mFileName := FileOf(ASet.Id);
  if Length(mBytes) > FMaxBytes then
  begin
    // Zu groß für die Grenze: nicht sichern, auch keinen älteren Stand dieses Satzes behalten.
    if TFile.Exists(mFileName) then
    begin
      TFile.Delete(mFileName);
    end;
    Exit;
  end;
  TDirectory.CreateDirectory(FFolder);
  TAtlasTextFile.Replace(mFileName, mBytes);
  Shrink;
end;

procedure TAtlasUndoFileStore.Shrink;
var
  mFiles: TArray<string>;
  mTotal: Int64;
  mIndex: Integer;
begin
  mFiles := SetFiles;
  mTotal := 0;
  for mIndex := 0 to High(mFiles) do
  begin
    Inc(mTotal, TFile.GetSize(mFiles[mIndex]));
  end;
  mIndex := 0;
  while (mTotal > FMaxBytes) and (mIndex < Length(mFiles)) do
  begin
    Dec(mTotal, TFile.GetSize(mFiles[mIndex]));
    TFile.Delete(mFiles[mIndex]);
    Inc(mIndex);
  end;
end;

procedure TAtlasUndoFileStore.Delete(AId: Integer);
begin
  if TFile.Exists(FileOf(AId)) then
  begin
    TFile.Delete(FileOf(AId));
  end;
end;

function TAtlasUndoFileStore.Load: TArray<TAtlasChangeSet>;

  /// <summary>Inhalt von AFileName als JSON; nil, wenn die Datei nicht lesbar ist.</summary>
  function ReadSet(const AFileName: string): TJSONValue;
  begin
    try
      Result := TJSONObject.ParseJSONValue(TEncoding.UTF8.GetString(TAtlasTextFile.ReadAllBytes(AFileName)));
    except
      on EStreamError do
        Result := nil;
    end;
  end;

var
  mFileName: string;
  mValue: TJSONValue;
  mChangeSet: TAtlasChangeSet;
begin
  Result := nil;
  for mFileName in SetFiles do
  begin
    // Nicht lesbare oder kaputte Datei: überspringen (siehe Kopf). Lesen teilt Löschen (Bericht M5).
    mValue := ReadSet(mFileName);
    try
      if FromJson(mValue, mChangeSet) then
      begin
        Result := Result + [mChangeSet];
      end;
    finally
      mValue.Free;
    end;
  end;
end;

procedure TAtlasUndoFileStore.Clear;
var
  mFileName: string;
begin
  for mFileName in SetFiles do
  begin
    TFile.Delete(mFileName);
  end;
end;

end.
