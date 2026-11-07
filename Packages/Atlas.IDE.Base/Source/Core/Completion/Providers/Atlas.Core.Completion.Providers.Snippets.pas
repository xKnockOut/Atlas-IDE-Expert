unit Atlas.Core.Completion.Providers.Snippets;

// Code-Vorlagen als Datenquelle der Vervollständigung (#51, #408): lokal,
// ohne Server. Vorlagen stehen nur am Anfang einer Anweisung bzw. Deklaration
// (vor dem getippten Wort nur Einrückung), nicht hinter einem Punkt, nicht in
// Kommentaren oder Strings und nicht in Listen mit Auslösezeichen ("[", ";").
// Die Liste filtert über das Kürzel; Detail ist der Name, das Detailpanel
// zeigt Beschreibung und Text.

interface

uses
  System.SysUtils,
  System.SyncObjs,
  Atlas.Core.Completion.Contract,
  Atlas.Core.Completion.Snippets,
  Atlas.Core.Completion.Internals.Async;

type
  TAtlasSnippetCompletionProvider = class(TAtlasAsyncCompletionProvider)
  private
    FSnippetLock: TCriticalSection;
    FSnippets: TAtlasSnippetList;
    FEnabled: Boolean;
  protected
    function Prepare(const AContext: TAtlasContext; out AData: TObject): Boolean; override;
    function Fetch(const AContext: TAtlasContext; AData: TObject; const ACancelled: TAtlasCancelledFunc;
      const AEmit: TAtlasEmitProc; out AState: TAtlasFetchState): TAtlasCompletionItems; override;
  public
    constructor Create(const ASnippets: TAtlasSnippetList);
    destructor Destroy; override;
    procedure SetSnippets(const ASnippets: TAtlasSnippetList);
    /// <summary>Alle Vorlagen der Quelle (Erzeugen-Menü, #719); threadsicher.</summary>
    function Snippets: TAtlasSnippetList;
    /// <summary>Abgeschaltet (Einstellung Snippets) liefert die Quelle nichts. Im Hauptthread setzen.</summary>
    property Enabled: Boolean read FEnabled write FEnabled;
    /// <summary>Passt die Stelle? ALineBefore: Zeile bis zum Cursor, APrefix: getipptes Wort davor.</summary>
    class function IsSnippetContext(const ALineBefore, APrefix: string): Boolean; static;
    class function Items(const ASnippets: TAtlasSnippetList): TAtlasCompletionItems; static;
  end;

implementation

const
  /// <summary>Hinter den Einträgen des Servers, wenn beide gleich gut passen.</summary>
  cSnippetRank = 1000000;

/// <summary>Zeile ALine (0-basiert) aus AText, ohne den ganzen Text zu zerlegen.</summary>
function LineOf(const AText: string; ALine: Integer): string;
var
  mIndex, mLine, mStart: Integer;
begin
  mLine := 0;
  mStart := 1;
  mIndex := 1;
  while (mLine < ALine) and (mIndex <= Length(AText)) do
  begin
    if AText[mIndex] = #10 then
    begin
      Inc(mLine);
      mStart := mIndex + 1;
    end;
    Inc(mIndex);
  end;
  if mLine < ALine then
  begin
    Exit('');
  end;
  mIndex := mStart;
  while (mIndex <= Length(AText)) and (AText[mIndex] <> #10) and (AText[mIndex] <> #13) do
  begin
    Inc(mIndex);
  end;
  Result := Copy(AText, mStart, mIndex - mStart);
end;

{ TAtlasSnippetCompletionProvider }

constructor TAtlasSnippetCompletionProvider.Create(const ASnippets: TAtlasSnippetList);
begin
  inherited Create;
  FSnippetLock := TCriticalSection.Create;
  FSnippets := ASnippets;
  FEnabled := True;
end;

destructor TAtlasSnippetCompletionProvider.Destroy;
begin
  // Erst die Threads beenden, dann die Sperre freigeben, die Fetch benutzt.
  Shutdown;
  FSnippetLock.Free;
  inherited Destroy;
end;

procedure TAtlasSnippetCompletionProvider.SetSnippets(const ASnippets: TAtlasSnippetList);
begin
  FSnippetLock.Enter;
  try
    FSnippets := ASnippets;
  finally
    FSnippetLock.Leave;
  end;
end;

function TAtlasSnippetCompletionProvider.Snippets: TAtlasSnippetList;
begin
  FSnippetLock.Enter;
  try
    Result := FSnippets;
  finally
    FSnippetLock.Leave;
  end;
end;

class function TAtlasSnippetCompletionProvider.IsSnippetContext(const ALineBefore, APrefix: string): Boolean;
var
  mBefore: string;
  mIndex: Integer;
  mQuoted: Boolean;
begin
  Result := False;
  if Length(APrefix) > Length(ALineBefore) then
  begin
    Exit;
  end;
  mBefore := Copy(ALineBefore, 1, Length(ALineBefore) - Length(APrefix));
  // Nur Einrückung vor dem Wort; damit auch kein Punkt, kein String und kein //-Kommentar davor.
  for mIndex := 1 to Length(mBefore) do
  begin
    if (mBefore[mIndex] <> ' ') and (mBefore[mIndex] <> #9) then
    begin
      Exit;
    end;
  end;
  mQuoted := False;
  for mIndex := 1 to Length(APrefix) do
  begin
    if APrefix[mIndex] = '''' then
    begin
      mQuoted := not mQuoted;
    end;
  end;
  Result := not mQuoted;
end;

class function TAtlasSnippetCompletionProvider.Items(const ASnippets: TAtlasSnippetList): TAtlasCompletionItems;
var
  mIndex: Integer;
  mItem: TAtlasCompletionItem;
  mSnippet: TAtlasSnippet;
begin
  Result := nil;
  for mIndex := 0 to High(ASnippets) do
  begin
    mSnippet := ASnippets[mIndex];
    mItem := Default(TAtlasCompletionItem);
    mItem.Name := mSnippet.Prefix;
    mItem.Kind := TAtlasItemKind.Snippet;
    mItem.Signature := mSnippet.Name;
    mItem.Documentation := TAtlasSnippets.PlainText(mSnippet.Body);
    if mSnippet.Description <> '' then
    begin
      mItem.Documentation := mSnippet.Description + #10#10 + mItem.Documentation;
    end;
    mItem.Snippet := mSnippet.Body;
    mItem.UnitUsed := True;
    mItem.Rank := cSnippetRank + mIndex;
    Result := Result + [mItem];
  end;
end;

function TAtlasSnippetCompletionProvider.Prepare(const AContext: TAtlasContext; out AData: TObject): Boolean;
begin
  AData := nil;
  Result := FEnabled and (AContext.Kind = TAtlasContextKind.Identifier) and (AContext.Trigger = '');
end;

function TAtlasSnippetCompletionProvider.Fetch(const AContext: TAtlasContext; AData: TObject;
  const ACancelled: TAtlasCancelledFunc; const AEmit: TAtlasEmitProc; out AState: TAtlasFetchState): TAtlasCompletionItems;
var
  mSnippets: TAtlasSnippetList;
begin
  AState := Default(TAtlasFetchState);
  Result := nil;
  if not IsSnippetContext(Copy(LineOf(AContext.Text, AContext.Line), 1, AContext.Character), AContext.Prefix) then
  begin
    Exit;
  end;
  FSnippetLock.Enter;
  try
    mSnippets := FSnippets;
  finally
    FSnippetLock.Leave;
  end;
  Result := Items(mSnippets);
end;

end.
