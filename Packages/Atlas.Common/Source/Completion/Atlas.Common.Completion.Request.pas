unit Atlas.Common.Completion.Request;

// Anfrage der Vervollständigung: alles, was die Fälle von
// textDocument/completion je Anfrage brauchen, in einem Objekt statt in neun Parametern. Einmal
// berechnete Werte (Zeilen, Zeilenende, Index der eigenen Unit) bleiben im Objekt. Die Typen der
// Vervollständigung (Kontext, Eintrag, Liste) stehen in Atlas.Common.Completion.Contract; Sprachserver und
// Editing teilen beide.
//
// Die Zeilenhelfer behalten bewusst die Semantik der früheren freien Funktionen (LineBefore, LineOf,
// TextLines, OffsetOf): Zeilen werden an #10 getrennt, ein #13 davor fällt weg; LineBefore endet auch an
// einem einzelnen #13. Sie lesen deshalb immer den Text, auch wenn ein Dokument vorliegt.

interface

{$SCOPEDENUMS ON}

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Completion.Contract;

type
  /// <summary>Alles, was die Fälle der Vervollständigung je Anfrage brauchen (4.2 Schritt 4).
  /// Der Aufrufer besitzt das Objekt (try … finally Free); Baum, Resolver und Index gehören ihm nicht.
  /// Einmal berechnete Werte (Zeilen, Index der eigenen Unit) bleiben im Objekt.</summary>
  TCompletionRequest = class
  private
    FText: string;
    FFileName: string;
    FUri: string;
    FPosition: TTextPosition;
    FTree: TSyntaxTree;
    FResolver: TNameResolver;
    FIndex: ISymbolIndex;
    FReadText: TDocumentReadText;
    FMatching: TCompletionMatching;
    FSettings: TCompletionSettings;
    FTrigger: string;
    FLines: TArray<string>;
    FLinesReady: Boolean;
    FUnitIndex: TUnitIndex;
    FUnitIndexReady: Boolean;
    FIdeTypes: TArray<TIdeTypeEntry>;
    procedure SetTree(AValue: TSyntaxTree);
    procedure SetResolver(AValue: TNameResolver);
  public
    /// <summary>Aus einem offenen Dokument (Handle); liest dessen Text einmal.</summary>
    constructor Create(const ADocument: ITextDocument; const AFileName: string;
      const APosition: TTextPosition); overload;
    /// <summary>Aus Text (Tests und Kompatibilitäts-Überladungen). Matching unscharf, Settings Standard.</summary>
    constructor Create(const AText, AFileName: string; const APosition: TTextPosition); overload;
    /// <summary>Zeile ALine ohne Zeilenende; '' außerhalb.</summary>
    function LineText(ALine: Integer): string;
    /// <summary>Zeile der Position bis zum Cursor; endet am Zeilenende (#10 oder #13).</summary>
    function LineBefore: string;
    /// <summary>Alle Zeilen ohne Zeilenende, einmal geteilt.</summary>
    function Lines: TArray<string>;
    /// <summary>Offset (0-basiert) von APosition im Text; Zeilen zählen an #10, das Zeichen wird nicht
    /// begrenzt.</summary>
    function OffsetAt(const APosition: TTextPosition): Integer;
    /// <summary>#13#10, wenn der Text irgendwo CRLF enthält, sonst #10.</summary>
    function LineBreak: string;
    /// <summary>Index der eigenen Unit aus dem Baum (Resolver.ExtractedUnit), einmal je Baum und Resolver.
    /// </summary>
    function UnitIndex: TUnitIndex;
    /// <summary>Text des Dokuments.</summary>
    property Text: string read FText;
    property FileName: string read FFileName;
    property Position: TTextPosition read FPosition;
    /// <summary>URI des Dokuments für Einstellungen je Dokument; '' ohne.</summary>
    property Uri: string read FUri write FUri;
    property Tree: TSyntaxTree read FTree write SetTree;
    property Resolver: TNameResolver read FResolver write SetResolver;
    property Index: ISymbolIndex read FIndex write FIndex;
    property ReadText: TDocumentReadText read FReadText write FReadText;
    property Matching: TCompletionMatching read FMatching write FMatching;
    property Settings: TCompletionSettings read FSettings write FSettings;
    /// <summary>context.triggerCharacter der Anfrage; '' ohne.</summary>
    property Trigger: string read FTrigger write FTrigger;
    /// <summary>Typen aus den Packages der IDE (atlas/ideTypes), auch ohne Quelltext; nil ohne Plugin.</summary>
    property IdeTypes: TArray<TIdeTypeEntry> read FIdeTypes write FIdeTypes;
  end;

/// <summary>Zeilen von AText ohne Zeilenende (getrennt an LF, ein CR davor fällt weg).</summary>
function TextLines(const AText: string): TArray<string>;
/// <summary>Zeilen von AFileName, je Datei einmal gelesen; AText für die eigene Datei
/// AOwnFile. False, wenn die Datei nicht lesbar ist (auch das merkt sich ACache).</summary>
function CachedLines(ACache: TDictionary<string, TArray<string>>; const AFileName, AOwnFile, AText: string;
  const AReadText: TDocumentReadText; out ALines: TArray<string>): Boolean;

implementation

uses
  System.Math,
  System.StrUtils,
  Atlas.Text.Lines;

{ TCompletionRequest }

constructor TCompletionRequest.Create(const ADocument: ITextDocument; const AFileName: string;
  const APosition: TTextPosition);
begin
  Create(ADocument.Text, AFileName, APosition);
  FUri := ADocument.Uri;
end;

constructor TCompletionRequest.Create(const AText, AFileName: string; const APosition: TTextPosition);
begin
  inherited Create;
  FText := AText;
  FFileName := AFileName;
  FPosition := APosition;
  FMatching := TCompletionMatching.Fuzzy;
  FSettings := TCompletionSettings.Default;
end;

procedure TCompletionRequest.SetTree(AValue: TSyntaxTree);
begin
  FTree := AValue;
  FUnitIndexReady := False;
end;

procedure TCompletionRequest.SetResolver(AValue: TNameResolver);
begin
  FResolver := AValue;
  FUnitIndexReady := False;
end;

function TCompletionRequest.LineText(ALine: Integer): string;
begin
  Lines;
  if (ALine < 0) or (ALine > High(FLines)) then
  begin
    Exit('');
  end;
  Result := FLines[ALine];
end;

function TCompletionRequest.LineBefore: string;
var
  mLine, mStart, mStop: Integer;
begin
  mStart := 1;
  for mLine := 1 to FPosition.Line do
  begin
    mStart := PosEx(#10, FText, mStart) + 1;
    if mStart = 1 then
    begin
      Exit('');
    end;
  end;
  mStop := mStart;
  while (mStop <= Length(FText)) and (FText[mStop] <> #10) and (FText[mStop] <> #13) do
  begin
    Inc(mStop);
  end;
  Result := Copy(FText, mStart, Min(FPosition.Character, mStop - mStart));
end;

function TCompletionRequest.Lines: TArray<string>;
var
  mIndex: Integer;
begin
  if not FLinesReady then
  begin
    FLines := nil;
    FLines := FText.Split([#10]);
    for mIndex := 0 to High(FLines) do
    begin
      if FLines[mIndex].EndsWith(#13) then
      begin
        FLines[mIndex] := Copy(FLines[mIndex], 1, Length(FLines[mIndex]) - 1);
      end;
    end;
    FLinesReady := True;
  end;
  Result := FLines;
end;

function TCompletionRequest.OffsetAt(const APosition: TTextPosition): Integer;
var
  mIndex, mLine: Integer;
begin
  mLine := 0;
  mIndex := 1;
  while (mLine < APosition.Line) and (mIndex <= Length(FText)) do
  begin
    if FText[mIndex] = #10 then
    begin
      Inc(mLine);
    end;
    Inc(mIndex);
  end;
  Result := mIndex - 1 + APosition.Character;
end;

function TCompletionRequest.LineBreak: string;
begin
  if Pos(#13#10, FText) > 0 then
  begin
    Result := #13#10;
  end
  else
  begin
    Result := #10;
  end;
end;

function TCompletionRequest.UnitIndex: TUnitIndex;
begin
  if not FUnitIndexReady then
  begin
    FUnitIndex := FResolver.ExtractedUnit(FTree, FFileName);
    FUnitIndexReady := True;
  end;
  Result := FUnitIndex;
end;

function TextLines(const AText: string): TArray<string>;
begin
  Result := TTextLines.SplitAtLineFeed(AText);
end;

function CachedLines(ACache: TDictionary<string, TArray<string>>; const AFileName, AOwnFile, AText: string;
  const AReadText: TDocumentReadText; out ALines: TArray<string>): Boolean;
var
  mKey, mSource: string;
begin
  mKey := AnsiUpperCase(AFileName);
  if not ACache.TryGetValue(mKey, ALines) then
  begin
    ALines := nil;
    if SameText(AFileName, AOwnFile) then
    begin
      ALines := TextLines(AText);
    end
    else if Assigned(AReadText) and AReadText(AFileName, mSource) then
    begin
      ALines := TextLines(mSource);
    end;
    // nil steht für "nicht lesbar"; TextLines liefert sonst mindestens eine Zeile.
    ACache.Add(mKey, ALines);
  end;
  Result := ALines <> nil;
end;

end.
