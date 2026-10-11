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
    Marker = '@bookmark';
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
  Token: TPascalToken;
  Content: string;
  Bookmark: TBookmark;
begin
  Result := nil;
  if Pos(Marker, AText) = 0 then
    Exit;
  for Token in TPascalLexer.Tokenize(AText) do
  begin
    if Token.Kind <> TPascalTokenKind.Comment then
      Continue;
    if StartsStr('//', Token.Text) then
      Content := Copy(Token.Text, 3, MaxInt)
    else if StartsStr('{', Token.Text) and not StartsStr('{$', Token.Text) then
      Content := Copy(Token.Text, 2, Length(Token.Text) - 2)
    else if StartsStr('(*', Token.Text) then
      Content := Copy(Token.Text, 3, Length(Token.Text) - 4)
    else
      Continue;
    Content := Trim(Content);
    if not StartsText(Marker + ' ', Content) then
      Continue;
    Bookmark.Name := Trim(Copy(Content, Length(Marker) + 2, MaxInt));
    if Bookmark.Name = '' then
      Continue;
    Bookmark.Range := TTextRange.Create(Token.StartPos, Token.EndPos);
    Result := Result + [Bookmark];
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
  Key, Text: string;
  Entry: TEntry;
begin
  Key := LowerCase(AFileName);
  TMonitor.Enter(FLock);
  try
    if FEntries.TryGetValue(Key, Entry) and (Entry.Stamp = AStamp) then
      Exit;
  finally
    TMonitor.Exit(FLock);
  end;
  Entry.FileName := AFileName;
  Entry.Stamp := AStamp;
  if AReadText(AFileName, Text) then
    Entry.Items := TBookmarks.Find(Text)
  else
    Entry.Items := nil;
  TMonitor.Enter(FLock);
  try
    FEntries.AddOrSetValue(Key, Entry);
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TBookmarkStore.Retain(const AFileNames: TArray<string>);
var
  Keep: TDictionary<string, Boolean>;
  Name: string;
  Key: string;
begin
  Keep := TDictionary<string, Boolean>.Create;
  try
    for Name in AFileNames do
      Keep.AddOrSetValue(LowerCase(Name), True);
    TMonitor.Enter(FLock);
    try
      for Key in FEntries.Keys.ToArray do
        if not Keep.ContainsKey(Key) then
          FEntries.Remove(Key);
    finally
      TMonitor.Exit(FLock);
    end;
  finally
    Keep.Free;
  end;
end;

function TBookmarkStore.All: TArray<TBookmarkHit>;
var
  Pair: TPair<string, TEntry>;
  Hit: TBookmarkHit;
  Bookmark: TBookmark;
begin
  Result := nil;
  TMonitor.Enter(FLock);
  try
    for Pair in FEntries do
      for Bookmark in Pair.Value.Items do
      begin
        Hit.FileName := Pair.Value.FileName;
        Hit.Bookmark := Bookmark;
        Result := Result + [Hit];
      end;
  finally
    TMonitor.Exit(FLock);
  end;
end;

end.
