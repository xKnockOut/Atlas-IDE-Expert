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
      const AEmit: TAtlasEmitProc; out AIncomplete: Boolean): TAtlasCompletionItems; override;
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
  SnippetRank = 1000000;

/// <summary>Zeile ALine (0-basiert) aus AText, ohne den ganzen Text zu zerlegen.</summary>
function LineOf(const AText: string; ALine: Integer): string;
var
  Index, Line, Start: Integer;
begin
  Line := 0;
  Start := 1;
  Index := 1;
  while (Line < ALine) and (Index <= Length(AText)) do
  begin
    if AText[Index] = #10 then
    begin
      Inc(Line);
      Start := Index + 1;
    end;
    Inc(Index);
  end;
  if Line < ALine then
    Exit('');
  Index := Start;
  while (Index <= Length(AText)) and (AText[Index] <> #10) and (AText[Index] <> #13) do
    Inc(Index);
  Result := Copy(AText, Start, Index - Start);
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
  Before: string;
  Index: Integer;
  Quoted: Boolean;
begin
  Result := False;
  if Length(APrefix) > Length(ALineBefore) then
    Exit;
  Before := Copy(ALineBefore, 1, Length(ALineBefore) - Length(APrefix));
  // Nur Einrückung vor dem Wort; damit auch kein Punkt, kein String und kein //-Kommentar davor.
  for Index := 1 to Length(Before) do
    if (Before[Index] <> ' ') and (Before[Index] <> #9) then
      Exit;
  Quoted := False;
  for Index := 1 to Length(APrefix) do
    if APrefix[Index] = '''' then
      Quoted := not Quoted;
  Result := not Quoted;
end;

class function TAtlasSnippetCompletionProvider.Items(const ASnippets: TAtlasSnippetList): TAtlasCompletionItems;
var
  Index: Integer;
  Item: TAtlasCompletionItem;
  Snippet: TAtlasSnippet;
begin
  Result := nil;
  for Index := 0 to High(ASnippets) do
  begin
    Snippet := ASnippets[Index];
    Item := Default(TAtlasCompletionItem);
    Item.Name := Snippet.Prefix;
    Item.Kind := TAtlasItemKind.Snippet;
    Item.Signature := Snippet.Name;
    Item.Documentation := TAtlasSnippets.PlainText(Snippet.Body);
    if Snippet.Description <> '' then
      Item.Documentation := Snippet.Description + #10#10 + Item.Documentation;
    Item.Snippet := Snippet.Body;
    Item.UnitUsed := True;
    Item.Rank := SnippetRank + Index;
    Result := Result + [Item];
  end;
end;

function TAtlasSnippetCompletionProvider.Prepare(const AContext: TAtlasContext; out AData: TObject): Boolean;
begin
  AData := nil;
  Result := FEnabled and (AContext.Kind = TAtlasContextKind.Identifier) and (AContext.Trigger = '');
end;

function TAtlasSnippetCompletionProvider.Fetch(const AContext: TAtlasContext; AData: TObject;
  const ACancelled: TAtlasCancelledFunc; const AEmit: TAtlasEmitProc; out AIncomplete: Boolean): TAtlasCompletionItems;
var
  Snippets: TAtlasSnippetList;
begin
  AIncomplete := False;
  Result := nil;
  if not IsSnippetContext(Copy(LineOf(AContext.Text, AContext.Line), 1, AContext.Character), AContext.Prefix) then
    Exit;
  FSnippetLock.Enter;
  try
    Snippets := FSnippets;
  finally
    FSnippetLock.Leave;
  end;
  Result := Items(Snippets);
end;

end.
