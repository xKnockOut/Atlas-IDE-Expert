unit Atlas.Core.Tracker.IssueCache;

// Zwischenspeicher der Issue-Vorschau (#1264), ohne VCL und Open Tools API.
// - Im Speicher je Tracker und Kennung, höchstens MaxMemory Einträge (der am
//   längsten nicht benutzte fällt heraus).
// - Auf der Platte unter %LOCALAPPDATA%\Atlas\issues\<Tracker>\<Kennung>.json
//   (Ordner von außen), höchstens MaxAgeDays alt; Älteres gilt als fehlend und
//   wird beim Aufräumen gelöscht. <Tracker> ist ein Prüfwert aus Server und
//   Projekt, damit weder Adresse noch Projekt im Dateinamen stehen.
// - Ohne Netz zeigt das Fenster den letzten Stand („Stand vom …“, Fetched).
// - Nie ein Token: TAtlasTrackerDetails hat keins. Signierte Adressen von
//   Anhängen (YouTrack "?sign=…") kommen ohne Abfrageteil auf die Platte.
// - Version 2 (#1279): Verknüpfungen mit Art und Zustand; Einträge der
//   Version 1 gelten als fehlend (ihnen fehlt die Art für den Baum).
// Nur im Hauptthread benutzen.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Core.Tracker.Contract;

type
  TAtlasTrackerIssueCache = class
  public const
    cMaxMemory = 50;
    cMaxAgeDays = 7;
    cVersion = 2;
  private type
    TEntry = record
      Details: TAtlasTrackerDetails;
      Used: Int64;
    end;
  private
    FFolder: string;
    FEntries: TDictionary<string, TEntry>;
    FClock: Int64;
    function FileOf(const ATarget: TAtlasTrackerTarget; const AKey: string): string;
    procedure Shrink;
  public
    /// <summary>AFolder: Ordner auf der Platte; '' = nur im Speicher.</summary>
    constructor Create(const AFolder: string);
    destructor Destroy; override;
    /// <summary>Merkt ADetails (im Speicher und auf der Platte).</summary>
    procedure Put(const ATarget: TAtlasTrackerTarget; const ADetails: TAtlasTrackerDetails);
    /// <summary>Letzter Stand zu AKey; von der Platte nur, wenn höchstens MaxAgeDays alt (ANow in UTC).</summary>
    function Get(const ATarget: TAtlasTrackerTarget; const AKey: string; ANow: TDateTime;
      out ADetails: TAtlasTrackerDetails): Boolean;
    /// <summary>Löscht Dateien, die älter als MaxAgeDays sind.</summary>
    procedure Prune(ANow: TDateTime);
    function Count: Integer;
    /// <summary>Schlüssel des Trackers: Prüfwert aus Server und Projekt (8 Hexziffern).</summary>
    class function TrackerId(const ATarget: TAtlasTrackerTarget): string; static;
    /// <summary>Kennung als Dateiname ("ATL-12", "#753" → "753").</summary>
    class function SafeName(const AKey: string): string; static;
    class function ToJson(const ADetails: TAtlasTrackerDetails): string; static;
    /// <summary>False bei ungültigem JSON, anderer Version oder ohne Kennung.</summary>
    class function FromJson(const AJson: string; out ADetails: TAtlasTrackerDetails): Boolean; static;
    property Folder: string read FFolder;
  end;

implementation

uses
  System.DateUtils,
  System.JSON,
  Atlas.Core.Tracker.Contract.Files,
  Atlas.Core.Tracker.Files;

function MemoryKey(const ATarget: TAtlasTrackerTarget; const AKey: string): string;
begin
  Result := LowerCase(ATarget.Server + '|' + ATarget.Project + '|' + Trim(AKey));
end;

function WithoutQuery(const AUrl: string): string;
begin
  Result := AUrl;
  if Pos('?', Result) > 0 then
  begin
    Result := Copy(Result, 1, Pos('?', Result) - 1);
  end;
end;

function IsoOf(AValue: TDateTime): string;
begin
  Result := '';
  if AValue > 0 then
  begin
    Result := DateToISO8601(AValue, True);
  end;
end;

function TimeOf(AObject: TJSONObject; const AName: string): TDateTime;
var
  mText: string;
begin
  Result := 0;
  mText := AObject.GetValue<string>(AName, '');
  if (mText = '') or not TryISO8601ToDate(mText, Result, True) then
  begin
    Result := 0;
  end;
end;

function LabelsJson(const ALabels: TArray<string>): TJSONArray;
var
  mText: string;
begin
  Result := TJSONArray.Create;
  for mText in ALabels do
  begin
    Result.Add(mText);
  end;
end;

function CommentsJson(const AComments: TArray<TAtlasTrackerComment>): TJSONArray;
var
  mItem: TJSONObject;
  mComment: TAtlasTrackerComment;
begin
  Result := TJSONArray.Create;
  for mComment in AComments do
  begin
    mItem := TJSONObject.Create;
    mItem.AddPair('author', mComment.Author);
    mItem.AddPair('created', IsoOf(mComment.Created));
    mItem.AddPair('text', mComment.Text);
    Result.AddElement(mItem);
  end;
end;

function AttachmentsJson(const AAttachments: TArray<TAtlasTrackerAttachment>): TJSONArray;
var
  mItem: TJSONObject;
  mAttachment: TAtlasTrackerAttachment;
begin
  Result := TJSONArray.Create;
  for mAttachment in AAttachments do
  begin
    mItem := TJSONObject.Create;
    mItem.AddPair('name', mAttachment.Name);
    mItem.AddPair('size', TJSONNumber.Create(mAttachment.Size));
    // Signierte Adressen (YouTrack "?sign=…") nicht auf die Platte.
    mItem.AddPair('url', WithoutQuery(mAttachment.Url));
    mItem.AddPair('mimeType', mAttachment.MimeType);
    mItem.AddPair('external', TJSONBool.Create(mAttachment.External));
    Result.AddElement(mItem);
  end;
end;

function LinksJson(const ALinks: TArray<TAtlasTrackerLink>): TJSONArray;
var
  mItem: TJSONObject;
  mLink: TAtlasTrackerLink;
begin
  Result := TJSONArray.Create;
  for mLink in ALinks do
  begin
    mItem := TJSONObject.Create;
    mItem.AddPair('key', mLink.Key);
    mItem.AddPair('title', mLink.Title);
    mItem.AddPair('relation', mLink.Relation);
    mItem.AddPair('page', mLink.Page);
    mItem.AddPair('local', TJSONBool.Create(mLink.Local));
    mItem.AddPair('kind', TAtlasTrackerLink.KindKey(mLink.Kind));
    mItem.AddPair('stateKnown', TJSONBool.Create(mLink.StateKnown));
    mItem.AddPair('linkState', mLink.State);
    mItem.AddPair('resolved', TJSONBool.Create(mLink.Resolved));
    Result.AddElement(mItem);
  end;
end;

function LabelsOf(AValue: TJSONValue): TArray<string>;
var
  mEntry: TJSONValue;
begin
  Result := nil;
  if AValue is TJSONArray then
  begin
    for mEntry in TJSONArray(AValue) do
    begin
      if mEntry is TJSONString then
      begin
        Result := Result + [TJSONString(mEntry).Value];
      end;
    end;
  end;
end;

function CommentOf(AItem: TJSONObject): TAtlasTrackerComment;
begin
  Result := Default(TAtlasTrackerComment);
  Result.Author := AItem.GetValue<string>('author', '');
  Result.Created := TimeOf(AItem, 'created');
  Result.Text := AItem.GetValue<string>('text', '');
end;

function CommentsOf(AValue: TJSONValue): TArray<TAtlasTrackerComment>;
var
  mEntry: TJSONValue;
begin
  Result := nil;
  if AValue is TJSONArray then
  begin
    for mEntry in TJSONArray(AValue) do
    begin
      if mEntry is TJSONObject then
      begin
        Result := Result + [CommentOf(TJSONObject(mEntry))];
      end;
    end;
  end;
end;

function AttachmentOf(AItem: TJSONObject): TAtlasTrackerAttachment;
begin
  Result := Default(TAtlasTrackerAttachment);
  Result.Name := AItem.GetValue<string>('name', '');
  Result.Size := AItem.GetValue<Int64>('size', -1);
  Result.Url := AItem.GetValue<string>('url', '');
  Result.MimeType := AItem.GetValue<string>('mimeType', '');
  Result.External := AItem.GetValue<Boolean>('external', False);
end;

function AttachmentsOf(AValue: TJSONValue): TArray<TAtlasTrackerAttachment>;
var
  mEntry: TJSONValue;
begin
  Result := nil;
  if AValue is TJSONArray then
  begin
    for mEntry in TJSONArray(AValue) do
    begin
      if mEntry is TJSONObject then
      begin
        Result := Result + [AttachmentOf(TJSONObject(mEntry))];
      end;
    end;
  end;
end;

function LinkOf(AItem: TJSONObject): TAtlasTrackerLink;
begin
  Result := Default(TAtlasTrackerLink);
  Result.Key := AItem.GetValue<string>('key', '');
  Result.Title := AItem.GetValue<string>('title', '');
  Result.Relation := AItem.GetValue<string>('relation', '');
  Result.Page := AItem.GetValue<string>('page', '');
  Result.Local := AItem.GetValue<Boolean>('local', False);
  Result.Kind := TAtlasTrackerLink.KindOf(AItem.GetValue<string>('kind', ''));
  Result.StateKnown := AItem.GetValue<Boolean>('stateKnown', False);
  Result.State := AItem.GetValue<string>('linkState', '');
  Result.Resolved := AItem.GetValue<Boolean>('resolved', False);
end;

function LinksOf(AValue: TJSONValue): TArray<TAtlasTrackerLink>;
var
  mEntry: TJSONValue;
begin
  Result := nil;
  if AValue is TJSONArray then
  begin
    for mEntry in TJSONArray(AValue) do
    begin
      if mEntry is TJSONObject then
      begin
        Result := Result + [LinkOf(TJSONObject(mEntry))];
      end;
    end;
  end;
end;

/// <summary>Einfache Felder (ohne Kennung und Listen) aus ARoot.</summary>
procedure ReadFields(ARoot: TJSONObject; var ADetails: TAtlasTrackerDetails);
begin
  ADetails.Number := ARoot.GetValue<Integer>('number', 0);
  ADetails.Title := ARoot.GetValue<string>('title', '');
  ADetails.Page := ARoot.GetValue<string>('page', '');
  ADetails.State := ARoot.GetValue<string>('state', '');
  ADetails.Priority := ARoot.GetValue<string>('priority', '');
  ADetails.Kind := ARoot.GetValue<string>('kind', '');
  ADetails.Assignee := ARoot.GetValue<string>('assignee', '');
  ADetails.Sprint := ARoot.GetValue<string>('sprint', '');
  ADetails.Created := TimeOf(ARoot, 'created');
  ADetails.Updated := TimeOf(ARoot, 'updated');
  ADetails.Description := ARoot.GetValue<string>('description', '');
  ADetails.CommentsLoaded := ARoot.GetValue<Boolean>('commentsLoaded', False);
  ADetails.Fetched := TimeOf(ARoot, 'fetched');
end;

{ TAtlasTrackerIssueCache }

constructor TAtlasTrackerIssueCache.Create(const AFolder: string);
begin
  inherited Create;
  FFolder := ExcludeTrailingPathDelimiter(AFolder);
  FEntries := TDictionary<string, TEntry>.Create;
end;

destructor TAtlasTrackerIssueCache.Destroy;
begin
  FEntries.Free;
  inherited;
end;

class function TAtlasTrackerIssueCache.TrackerId(const ATarget: TAtlasTrackerTarget): string;
var
  mText: string;
  mHash: Cardinal;
  mIndex: Integer;
begin
  // FNV-1a über die UTF-16-Zeichen; nur Unterscheidung, kein Schutz.
  mText := LowerCase(ATarget.Server + '|' + ATarget.Project);
  mHash := 2166136261;
  for mIndex := 1 to Length(mText) do
  begin
    mHash := mHash xor Ord(mText[mIndex]);
    mHash := Cardinal(UInt64(mHash) * 16777619);
  end;
  Result := LowerCase(IntToHex(mHash, 8));
end;

class function TAtlasTrackerIssueCache.SafeName(const AKey: string): string;
var
  mIndex: Integer;
begin
  Result := '';
  for mIndex := 1 to Length(AKey) do
  begin
    if CharInSet(AKey[mIndex], ['A'..'Z', 'a'..'z', '0'..'9', '-', '_']) then
    begin
      Result := Result + AKey[mIndex];
    end;
  end;
  Result := Copy(Result, 1, 64);
end;

function TAtlasTrackerIssueCache.FileOf(const ATarget: TAtlasTrackerTarget; const AKey: string): string;
var
  mName: string;
begin
  Result := '';
  mName := SafeName(AKey);
  if (FFolder = '') or (mName = '') or (ATarget.Server = '') then
  begin
    Exit;
  end;
  Result := TAtlasTrackerFiles.Join(TAtlasTrackerFiles.Join(FFolder, TrackerId(ATarget)), mName + '.json');
end;

class function TAtlasTrackerIssueCache.ToJson(const ADetails: TAtlasTrackerDetails): string;
var
  mRoot: TJSONObject;
begin
  mRoot := TJSONObject.Create;
  try
    mRoot.AddPair('version', TJSONNumber.Create(cVersion));
    mRoot.AddPair('key', ADetails.Key);
    mRoot.AddPair('number', TJSONNumber.Create(ADetails.Number));
    mRoot.AddPair('title', ADetails.Title);
    mRoot.AddPair('page', ADetails.Page);
    mRoot.AddPair('state', ADetails.State);
    mRoot.AddPair('priority', ADetails.Priority);
    mRoot.AddPair('kind', ADetails.Kind);
    mRoot.AddPair('assignee', ADetails.Assignee);
    mRoot.AddPair('sprint', ADetails.Sprint);
    mRoot.AddPair('labels', LabelsJson(ADetails.Labels));
    mRoot.AddPair('created', IsoOf(ADetails.Created));
    mRoot.AddPair('updated', IsoOf(ADetails.Updated));
    mRoot.AddPair('description', ADetails.Description);
    mRoot.AddPair('commentsLoaded', TJSONBool.Create(ADetails.CommentsLoaded));
    mRoot.AddPair('comments', CommentsJson(ADetails.Comments));
    mRoot.AddPair('attachments', AttachmentsJson(ADetails.Attachments));
    mRoot.AddPair('links', LinksJson(ADetails.Links));
    mRoot.AddPair('fetched', IsoOf(ADetails.Fetched));
    Result := mRoot.ToJSON;
  finally
    mRoot.Free;
  end;
end;

class function TAtlasTrackerIssueCache.FromJson(const AJson: string; out ADetails: TAtlasTrackerDetails): Boolean;
var
  mValue: TJSONValue;
  mRoot: TJSONObject;
begin
  ADetails := TAtlasTrackerDetails.Empty;
  Result := False;
  try
    mValue := TJSONObject.ParseJSONValue(AJson);
  except
    // Kaputte Datei: als fehlend werten.
    on Exception do
      mValue := nil;
  end;
  try
    if not (mValue is TJSONObject) then
    begin
      Exit;
    end;
    mRoot := TJSONObject(mValue);
    if mRoot.GetValue<Integer>('version', 0) <> cVersion then
    begin
      Exit;
    end;
    ADetails.Key := mRoot.GetValue<string>('key', '');
    if ADetails.Key = '' then
    begin
      Exit;
    end;
    ReadFields(mRoot, ADetails);
    ADetails.Labels := LabelsOf(mRoot.Values['labels']);
    ADetails.Comments := CommentsOf(mRoot.Values['comments']);
    ADetails.Attachments := AttachmentsOf(mRoot.Values['attachments']);
    ADetails.Links := LinksOf(mRoot.Values['links']);
    Result := True;
  finally
    mValue.Free;
  end;
end;

procedure TAtlasTrackerIssueCache.Shrink;
var
  mPair: TPair<string, TEntry>;
  mOldest: string;
  mUsed: Int64;
begin
  while FEntries.Count > cMaxMemory do
  begin
    mOldest := '';
    mUsed := High(Int64);
    for mPair in FEntries do
    begin
      if mPair.Value.Used < mUsed then
      begin
        mUsed := mPair.Value.Used;
        mOldest := mPair.Key;
      end;
    end;
    FEntries.Remove(mOldest);
  end;
end;

procedure TAtlasTrackerIssueCache.Put(const ATarget: TAtlasTrackerTarget; const ADetails: TAtlasTrackerDetails);
var
  mEntry: TEntry;
  mFile: string;
begin
  if ADetails.Key = '' then
  begin
    Exit;
  end;
  Inc(FClock);
  mEntry.Details := ADetails;
  mEntry.Used := FClock;
  FEntries.AddOrSetValue(MemoryKey(ATarget, ADetails.Key), mEntry);
  Shrink;
  mFile := FileOf(ATarget, ADetails.Key);
  if mFile = '' then
  begin
    Exit;
  end;
  // Kein Platz, keine Rechte: dann eben nur im Speicher.
  TAtlasTrackerFiles.Files.WriteText(mFile, ToJson(ADetails));
end;

function TAtlasTrackerIssueCache.Get(const ATarget: TAtlasTrackerTarget; const AKey: string; ANow: TDateTime;
  out ADetails: TAtlasTrackerDetails): Boolean;
var
  mEntry: TEntry;
  mFile, mKey, mText: string;
begin
  ADetails := TAtlasTrackerDetails.Empty;
  mKey := MemoryKey(ATarget, AKey);
  if FEntries.TryGetValue(mKey, mEntry) then
  begin
    Inc(FClock);
    mEntry.Used := FClock;
    FEntries.AddOrSetValue(mKey, mEntry);
    ADetails := mEntry.Details;
    Exit(True);
  end;
  mFile := FileOf(ATarget, AKey);
  Result := (mFile <> '') and TAtlasTrackerFiles.Files.ReadText(mFile, mText) and FromJson(mText, ADetails);
  if Result and ((ADetails.Fetched <= 0) or (ANow - ADetails.Fetched > cMaxAgeDays)) then
  begin
    Result := False;
  end;
  if not Result then
  begin
    ADetails := TAtlasTrackerDetails.Empty;
    Exit;
  end;
  Inc(FClock);
  mEntry.Details := ADetails;
  mEntry.Used := FClock;
  FEntries.AddOrSetValue(mKey, mEntry);
  Shrink;
end;

/// <summary>Datei des Caches gilt noch: lesbar, mit Abrufzeit und nicht älter als AMaxAge Tage.</summary>
function IsFresh(const AFiles: IAtlasTrackerFiles; const AFile: string; ANow: TDateTime; AMaxAge: Integer): Boolean;
var
  mText: string;
  mDetails: TAtlasTrackerDetails;
begin
  Result := AFiles.ReadText(AFile, mText) and TAtlasTrackerIssueCache.FromJson(mText, mDetails) and
    (mDetails.Fetched > 0) and (ANow - mDetails.Fetched <= AMaxAge);
end;

procedure TAtlasTrackerIssueCache.Prune(ANow: TDateTime);
var
  mFiles: IAtlasTrackerFiles;
  mFolder, mFile: string;
begin
  mFiles := TAtlasTrackerFiles.Files;
  if (FFolder = '') or not mFiles.FolderExists(FFolder) then
  begin
    Exit;
  end;
  // Aufräumen ist nur Pflege; gesperrte Dateien bleiben bis zum nächsten Mal, kaputte gelten als alt.
  for mFolder in mFiles.Folders(FFolder) do
  begin
    for mFile in mFiles.Files(mFolder, '*.json') do
    begin
      if not IsFresh(mFiles, mFile, ANow, cMaxAgeDays) then
      begin
        mFiles.DeleteFile(mFile);
      end;
    end;
    mFiles.RemoveEmptyFolder(mFolder);
  end;
end;

function TAtlasTrackerIssueCache.Count: Integer;
begin
  Result := FEntries.Count;
end;

end.
