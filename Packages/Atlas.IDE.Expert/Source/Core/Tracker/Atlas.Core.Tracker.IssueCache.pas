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
    MaxMemory = 50;
    MaxAgeDays = 7;
    Version = 2;
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
  System.IOUtils,
  System.DateUtils,
  System.JSON;

function MemoryKey(const ATarget: TAtlasTrackerTarget; const AKey: string): string;
begin
  Result := LowerCase(ATarget.Server + '|' + ATarget.Project + '|' + Trim(AKey));
end;

function WithoutQuery(const AUrl: string): string;
begin
  Result := AUrl;
  if Pos('?', Result) > 0 then
    Result := Copy(Result, 1, Pos('?', Result) - 1);
end;

function IsoOf(AValue: TDateTime): string;
begin
  Result := '';
  if AValue > 0 then
    Result := DateToISO8601(AValue, True);
end;

function TimeOf(AObject: TJSONObject; const AName: string): TDateTime;
var
  mText: string;
begin
  Result := 0;
  mText := AObject.GetValue<string>(AName, '');
  if (mText = '') or not TryISO8601ToDate(mText, Result, True) then
    Result := 0;
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
    if CharInSet(AKey[mIndex], ['A'..'Z', 'a'..'z', '0'..'9', '-', '_']) then
      Result := Result + AKey[mIndex];
  Result := Copy(Result, 1, 64);
end;

function TAtlasTrackerIssueCache.FileOf(const ATarget: TAtlasTrackerTarget; const AKey: string): string;
var
  mName: string;
begin
  Result := '';
  mName := SafeName(AKey);
  if (FFolder = '') or (mName = '') or (ATarget.Server = '') then
    Exit;
  Result := TPath.Combine(TPath.Combine(FFolder, TrackerId(ATarget)), mName + '.json');
end;

class function TAtlasTrackerIssueCache.ToJson(const ADetails: TAtlasTrackerDetails): string;
var
  mRoot, mItem: TJSONObject;
  mList: TJSONArray;
  mText: string;
  mComment: TAtlasTrackerComment;
  mAttachment: TAtlasTrackerAttachment;
  mLink: TAtlasTrackerLink;
begin
  mRoot := TJSONObject.Create;
  try
    mRoot.AddPair('version', TJSONNumber.Create(Version));
    mRoot.AddPair('key', ADetails.Key);
    mRoot.AddPair('number', TJSONNumber.Create(ADetails.Number));
    mRoot.AddPair('title', ADetails.Title);
    mRoot.AddPair('page', ADetails.Page);
    mRoot.AddPair('state', ADetails.State);
    mRoot.AddPair('priority', ADetails.Priority);
    mRoot.AddPair('kind', ADetails.Kind);
    mRoot.AddPair('assignee', ADetails.Assignee);
    mRoot.AddPair('sprint', ADetails.Sprint);
    mList := TJSONArray.Create;
    for mText in ADetails.Labels do
      mList.Add(mText);
    mRoot.AddPair('labels', mList);
    mRoot.AddPair('created', IsoOf(ADetails.Created));
    mRoot.AddPair('updated', IsoOf(ADetails.Updated));
    mRoot.AddPair('description', ADetails.Description);
    mRoot.AddPair('commentsLoaded', TJSONBool.Create(ADetails.CommentsLoaded));
    mList := TJSONArray.Create;
    for mComment in ADetails.Comments do
    begin
      mItem := TJSONObject.Create;
      mItem.AddPair('author', mComment.Author);
      mItem.AddPair('created', IsoOf(mComment.Created));
      mItem.AddPair('text', mComment.Text);
      mList.AddElement(mItem);
    end;
    mRoot.AddPair('comments', mList);
    mList := TJSONArray.Create;
    for mAttachment in ADetails.Attachments do
    begin
      mItem := TJSONObject.Create;
      mItem.AddPair('name', mAttachment.Name);
      mItem.AddPair('size', TJSONNumber.Create(mAttachment.Size));
      // Signierte Adressen (YouTrack "?sign=…") nicht auf die Platte.
      mItem.AddPair('url', WithoutQuery(mAttachment.Url));
      mItem.AddPair('mimeType', mAttachment.MimeType);
      mItem.AddPair('external', TJSONBool.Create(mAttachment.External));
      mList.AddElement(mItem);
    end;
    mRoot.AddPair('attachments', mList);
    mList := TJSONArray.Create;
    for mLink in ADetails.Links do
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
      mList.AddElement(mItem);
    end;
    mRoot.AddPair('links', mList);
    mRoot.AddPair('fetched', IsoOf(ADetails.Fetched));
    Result := mRoot.ToJSON;
  finally
    mRoot.Free;
  end;
end;

class function TAtlasTrackerIssueCache.FromJson(const AJson: string; out ADetails: TAtlasTrackerDetails): Boolean;
var
  mValue, mEntry: TJSONValue;
  mRoot, mItem: TJSONObject;
  mComment: TAtlasTrackerComment;
  mAttachment: TAtlasTrackerAttachment;
  mLink: TAtlasTrackerLink;
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
      Exit;
    mRoot := TJSONObject(mValue);
    if mRoot.GetValue<Integer>('version', 0) <> Version then
      Exit;
    ADetails.Key := mRoot.GetValue<string>('key', '');
    if ADetails.Key = '' then
      Exit;
    ADetails.Number := mRoot.GetValue<Integer>('number', 0);
    ADetails.Title := mRoot.GetValue<string>('title', '');
    ADetails.Page := mRoot.GetValue<string>('page', '');
    ADetails.State := mRoot.GetValue<string>('state', '');
    ADetails.Priority := mRoot.GetValue<string>('priority', '');
    ADetails.Kind := mRoot.GetValue<string>('kind', '');
    ADetails.Assignee := mRoot.GetValue<string>('assignee', '');
    ADetails.Sprint := mRoot.GetValue<string>('sprint', '');
    if mRoot.Values['labels'] is TJSONArray then
      for mEntry in TJSONArray(mRoot.Values['labels']) do
        if mEntry is TJSONString then
          ADetails.Labels := ADetails.Labels + [TJSONString(mEntry).Value];
    ADetails.Created := TimeOf(mRoot, 'created');
    ADetails.Updated := TimeOf(mRoot, 'updated');
    ADetails.Description := mRoot.GetValue<string>('description', '');
    ADetails.CommentsLoaded := mRoot.GetValue<Boolean>('commentsLoaded', False);
    if mRoot.Values['comments'] is TJSONArray then
      for mEntry in TJSONArray(mRoot.Values['comments']) do
        if mEntry is TJSONObject then
        begin
          mItem := TJSONObject(mEntry);
          mComment := Default(TAtlasTrackerComment);
          mComment.Author := mItem.GetValue<string>('author', '');
          mComment.Created := TimeOf(mItem, 'created');
          mComment.Text := mItem.GetValue<string>('text', '');
          ADetails.Comments := ADetails.Comments + [mComment];
        end;
    if mRoot.Values['attachments'] is TJSONArray then
      for mEntry in TJSONArray(mRoot.Values['attachments']) do
        if mEntry is TJSONObject then
        begin
          mItem := TJSONObject(mEntry);
          mAttachment := Default(TAtlasTrackerAttachment);
          mAttachment.Name := mItem.GetValue<string>('name', '');
          mAttachment.Size := mItem.GetValue<Int64>('size', -1);
          mAttachment.Url := mItem.GetValue<string>('url', '');
          mAttachment.MimeType := mItem.GetValue<string>('mimeType', '');
          mAttachment.External := mItem.GetValue<Boolean>('external', False);
          ADetails.Attachments := ADetails.Attachments + [mAttachment];
        end;
    if mRoot.Values['links'] is TJSONArray then
      for mEntry in TJSONArray(mRoot.Values['links']) do
        if mEntry is TJSONObject then
        begin
          mItem := TJSONObject(mEntry);
          mLink := Default(TAtlasTrackerLink);
          mLink.Key := mItem.GetValue<string>('key', '');
          mLink.Title := mItem.GetValue<string>('title', '');
          mLink.Relation := mItem.GetValue<string>('relation', '');
          mLink.Page := mItem.GetValue<string>('page', '');
          mLink.Local := mItem.GetValue<Boolean>('local', False);
          mLink.Kind := TAtlasTrackerLink.KindOf(mItem.GetValue<string>('kind', ''));
          mLink.StateKnown := mItem.GetValue<Boolean>('stateKnown', False);
          mLink.State := mItem.GetValue<string>('linkState', '');
          mLink.Resolved := mItem.GetValue<Boolean>('resolved', False);
          ADetails.Links := ADetails.Links + [mLink];
        end;
    ADetails.Fetched := TimeOf(mRoot, 'fetched');
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
  while FEntries.Count > MaxMemory do
  begin
    mOldest := '';
    mUsed := High(Int64);
    for mPair in FEntries do
      if mPair.Value.Used < mUsed then
      begin
        mUsed := mPair.Value.Used;
        mOldest := mPair.Key;
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
    Exit;
  Inc(FClock);
  mEntry.Details := ADetails;
  mEntry.Used := FClock;
  FEntries.AddOrSetValue(MemoryKey(ATarget, ADetails.Key), mEntry);
  Shrink;
  mFile := FileOf(ATarget, ADetails.Key);
  if mFile = '' then
    Exit;
  try
    ForceDirectories(ExtractFilePath(mFile));
    TFile.WriteAllText(mFile, ToJson(ADetails), TEncoding.UTF8);
  except
    // Kein Platz, keine Rechte: dann eben nur im Speicher.
    on Exception do
      Exit;
  end;
end;

function TAtlasTrackerIssueCache.Get(const ATarget: TAtlasTrackerTarget; const AKey: string; ANow: TDateTime;
  out ADetails: TAtlasTrackerDetails): Boolean;
var
  mEntry: TEntry;
  mFile, mKey: string;
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
  Result := False;
  mFile := FileOf(ATarget, AKey);
  if (mFile = '') or not FileExists(mFile) then
    Exit;
  try
    Result := FromJson(TFile.ReadAllText(mFile, TEncoding.UTF8), ADetails);
  except
    on Exception do
      Result := False;
  end;
  if Result and ((ADetails.Fetched <= 0) or (ANow - ADetails.Fetched > MaxAgeDays)) then
    Result := False;
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

procedure TAtlasTrackerIssueCache.Prune(ANow: TDateTime);
var
  mFolder, mFile: string;
  mDetails: TAtlasTrackerDetails;
  mFresh: Boolean;
begin
  if (FFolder = '') or not DirectoryExists(FFolder) then
    Exit;
  try
    for mFolder in TDirectory.GetDirectories(FFolder) do
    begin
      for mFile in TDirectory.GetFiles(mFolder, '*.json') do
      begin
        mFresh := False;
        try
          if FromJson(TFile.ReadAllText(mFile, TEncoding.UTF8), mDetails) and (mDetails.Fetched > 0) and
            (ANow - mDetails.Fetched <= MaxAgeDays) then
            mFresh := True;
        except
          // Kaputte Datei: bleibt nicht frisch.
          on Exception do
            ;
        end;
        if not mFresh then
          System.SysUtils.DeleteFile(mFile);
      end;
      if Length(TDirectory.GetFileSystemEntries(mFolder)) = 0 then
        RemoveDir(mFolder);
    end;
  except
    // Aufräumen ist nur Pflege; gesperrte Dateien bleiben bis zum nächsten Mal.
    on Exception do
      Exit;
  end;
end;

function TAtlasTrackerIssueCache.Count: Integer;
begin
  Result := FEntries.Count;
end;

end.
