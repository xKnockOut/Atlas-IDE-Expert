unit Atlas.Common.Editing.Bookmarks;

// Lesezeichen im Quelltext (#306): Kommentare "// @bookmark Name" bzw.
// "{ @bookmark Name }". Die Symbolsuche (workspace/symbol) findet sie über
// TBookmarkStore, der je Datei die Fundstellen hält und nur bei geändertem
// Stempel neu liest.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract;

type
  TBookmark = record
    Name: string;
    /// <summary>Bereich des Kommentars.</summary>
    Range: TTextRange;
  end;

  TBookmarkHit = record
    FileName: string;
    Bookmark: TBookmark;
  end;

  TBookmarks = class
  public const
    cMarker = '@bookmark';
  public
    /// <summary>Lesezeichen in AText in Reihenfolge.</summary>
    class function Find(const AText: string): TArray<TBookmark>; static;
  end;

  /// <summary>Liest den Text einer Datei; False, wenn sie fehlt.</summary>
  TBookmarkReadText = reference to function(const AFileName: string; out AText: string): Boolean;

  /// <summary>Lesezeichen je Datei, threadsicher.</summary>
  TBookmarkStore = class
  private type
    TEntry = record
      FileName: string;
      Stamp: Int64;
      Items: TArray<TBookmark>;
    end;
  private
    FLock: TObject;
    FEntries: TDictionary<string, TEntry>;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Liest AFileName neu, wenn sich AStamp geändert hat.</summary>
    procedure Update(const AFileName: string; AStamp: Int64; const AReadText: TBookmarkReadText);
    /// <summary>Vergisst alle Dateien außer AFileNames.</summary>
    procedure Retain(const AFileNames: TArray<string>);
    function All: TArray<TBookmarkHit>;
  end;

implementation

uses
  System.StrUtils,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Lexer;

{ TBookmarks }

class function TBookmarks.Find(const AText: string): TArray<TBookmark>;
var
  mToken: TPascalToken;
  mContent: string;
  mBookmark: TBookmark;
begin
  Result := nil;
  if Pos(cMarker, AText) = 0 then
  begin
    Exit;
  end;
  for mToken in TPascalLexer.Tokenize(AText) do
  begin
    if mToken.Kind <> TPascalTokenKind.Comment then
    begin
      Continue;
    end;
    if StartsStr('//', mToken.Text) then
    begin
      mContent := Copy(mToken.Text, 3, MaxInt);
    end
    else if StartsStr('{', mToken.Text) and not StartsStr('{$', mToken.Text) then
    begin
      mContent := Copy(mToken.Text, 2, Length(mToken.Text) - 2);
    end
    else if StartsStr('(*', mToken.Text) then
    begin
      mContent := Copy(mToken.Text, 3, Length(mToken.Text) - 4);
    end
    else
    begin
      Continue;
    end;
    mContent := Trim(mContent);
    if not StartsText(cMarker + ' ', mContent) then
    begin
      Continue;
    end;
    mBookmark.Name := Trim(Copy(mContent, Length(cMarker) + 2, MaxInt));
    if mBookmark.Name = '' then
    begin
      Continue;
    end;
    mBookmark.Range := TTextRange.Create(mToken.StartPos, mToken.EndPos);
    Result := Result + [mBookmark];
  end;
end;

{ TBookmarkStore }

constructor TBookmarkStore.Create;
begin
  inherited Create;
  FLock := TObject.Create;
  FEntries := TDictionary<string, TEntry>.Create;
end;

destructor TBookmarkStore.Destroy;
begin
  FEntries.Free;
  FLock.Free;
  inherited;
end;

procedure TBookmarkStore.Update(const AFileName: string; AStamp: Int64; const AReadText: TBookmarkReadText);
var
  mKey, mText: string;
  mEntry: TEntry;
begin
  mKey := LowerCase(AFileName);
  TMonitor.Enter(FLock);
  try
    if FEntries.TryGetValue(mKey, mEntry) and (mEntry.Stamp = AStamp) then
    begin
      Exit;
    end;
  finally
    TMonitor.Exit(FLock);
  end;
  mEntry.FileName := AFileName;
  mEntry.Stamp := AStamp;
  if AReadText(AFileName, mText) then
  begin
    mEntry.Items := TBookmarks.Find(mText);
  end
  else
  begin
    mEntry.Items := nil;
  end;
  TMonitor.Enter(FLock);
  try
    FEntries.AddOrSetValue(mKey, mEntry);
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TBookmarkStore.Retain(const AFileNames: TArray<string>);
var
  mKeep: TDictionary<string, Boolean>;
  mName: string;
  mKey: string;
begin
  mKeep := TDictionary<string, Boolean>.Create;
  try
    for mName in AFileNames do
    begin
      mKeep.AddOrSetValue(LowerCase(mName), True);
    end;
    TMonitor.Enter(FLock);
    try
      for mKey in FEntries.Keys.ToArray do
      begin
        if not mKeep.ContainsKey(mKey) then
        begin
          FEntries.Remove(mKey);
        end;
      end;
    finally
      TMonitor.Exit(FLock);
    end;
  finally
    mKeep.Free;
  end;
end;

function TBookmarkStore.All: TArray<TBookmarkHit>;
var
  mPair: TPair<string, TEntry>;
  mHit: TBookmarkHit;
  mBookmark: TBookmark;
begin
  Result := nil;
  TMonitor.Enter(FLock);
  try
    for mPair in FEntries do
    begin
      for mBookmark in mPair.Value.Items do
      begin
        mHit.FileName := mPair.Value.FileName;
        mHit.Bookmark := mBookmark;
        Result := Result + [mHit];
      end;
    end;
  finally
    TMonitor.Exit(FLock);
  end;
end;

end.
