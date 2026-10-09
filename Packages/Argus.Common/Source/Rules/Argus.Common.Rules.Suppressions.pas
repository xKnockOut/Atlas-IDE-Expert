unit Argus.Common.Rules.Suppressions;

// Unterdrückung einzelner Stellen per Kommentar:
//   x := 1; // lsp-ignore: regel-a, regel-b   gilt für diese Zeile
//   // lsp-ignore: regel-a                    allein in der Zeile: gilt für die nächste Zeile
//   // lsp-ignore-file: regel-a                gilt für die ganze Datei
// "*" steht für alle Regeln. Kommentare in { } und (* *) zählen ebenso.
// Merkt sich, welche Kommentare tatsächlich etwas unterdrückt haben, damit
// ungenutzte gemeldet werden können (#147).

interface

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Argus.Common.Documents.Contract,
  Argus.Common.Pascal.Contract;

type
  TSuppressionEntry = record
    /// <summary>Bereich des Kommentars.</summary>
    Range: TTextRange;
    /// <summary>Betroffene Zeile; -1 für die ganze Datei.</summary>
    TargetLine: Integer;
    /// <summary>Regelkennungen in Kleinbuchstaben, "*" für alle.</summary>
    Ids: TArray<string>;
    /// <summary>Der Kommentar steht allein in seiner Zeile.</summary>
    OwnLine: Boolean;
    Used: Boolean;
  end;

  TSuppressions = class
  private
    FEntries: TList<TSuppressionEntry>;
    class function Covers(const AIds: TArray<string>; const ARuleId: string): Boolean; static;
  public
    constructor Create(const ATokens: TArray<TPascalToken>);
    destructor Destroy; override;
    /// <summary>True, wenn ein Kommentar die Regel in ALine unterdrückt; markiert ihn als genutzt.</summary>
    function IsSuppressed(const ARuleId: string; ALine: Integer): Boolean;
    function Entries: TArray<TSuppressionEntry>;
    /// <summary>Kommentare, die bisher nichts unterdrückt haben.</summary>
    function UnusedEntries: TArray<TSuppressionEntry>;
    class function LineMarker: string; static;
    class function FileMarker: string; static;
  end;

implementation

function CommentBody(const AText: string): string;
begin
  Result := AText;
  if StartsText('//', Result) then
    Result := Copy(Result, 3, MaxInt)
  else if StartsText('{', Result) then
    Result := Copy(Result, 2, Length(Result) - 2)
  else if StartsText('(*', Result) then
    Result := Copy(Result, 3, Length(Result) - 4);
  Result := Trim(Result);
end;

function SplitIds(const AText: string): TArray<string>;
var
  I, Start: Integer;
  List: TList<string>;
begin
  // Trenner: Komma, Leerzeichen, Tabulator.
  List := TList<string>.Create;
  try
    Start := 1;
    for I := 1 to Length(AText) + 1 do
      if (I > Length(AText)) or CharInSet(AText[I], [',', ' ', #9]) then
      begin
        if I > Start then
          List.Add(LowerCase(Copy(AText, Start, I - Start)));
        Start := I + 1;
      end;
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

{ TSuppressions }

class function TSuppressions.LineMarker: string;
begin
  Result := 'lsp-ignore:';
end;

class function TSuppressions.FileMarker: string;
begin
  Result := 'lsp-ignore-file:';
end;

constructor TSuppressions.Create(const ATokens: TArray<TPascalToken>);
var
  I, J: Integer;
  Body, Lower: string;
  Entry: TSuppressionEntry;
  LastCodeLine: Integer;
  CodeAfter: Boolean;
begin
  inherited Create;
  FEntries := TList<TSuppressionEntry>.Create;
  LastCodeLine := -1;
  for I := 0 to High(ATokens) do
  begin
    if ATokens[I].Kind <> TPascalTokenKind.Comment then
    begin
      LastCodeLine := ATokens[I].EndPos.Line;
      Continue;
    end;
    Body := CommentBody(ATokens[I].Text);
    Lower := LowerCase(Body);
    Entry := Default(TSuppressionEntry);
    Entry.Range := TTextRange.Create(ATokens[I].StartPos, ATokens[I].EndPos);
    if StartsText(FileMarker, Lower) then
    begin
      Entry.Ids := SplitIds(Copy(Body, Length(FileMarker) + 1, MaxInt));
      Entry.TargetLine := -1;
    end
    else if StartsText(LineMarker, Lower) then
    begin
      Entry.Ids := SplitIds(Copy(Body, Length(LineMarker) + 1, MaxInt));
      if LastCodeLine = ATokens[I].StartPos.Line then
        Entry.TargetLine := ATokens[I].StartPos.Line
      else
        Entry.TargetLine := ATokens[I].EndPos.Line + 1;
    end
    else
      Continue;
    CodeAfter := False;
    J := I + 1;
    if (J <= High(ATokens)) and (ATokens[J].StartPos.Line = ATokens[I].EndPos.Line) then
      CodeAfter := True;
    Entry.OwnLine := (LastCodeLine <> ATokens[I].StartPos.Line) and not CodeAfter;
    FEntries.Add(Entry);
  end;
end;

destructor TSuppressions.Destroy;
begin
  FEntries.Free;
  inherited;
end;

class function TSuppressions.Covers(const AIds: TArray<string>; const ARuleId: string): Boolean;
var
  Id: string;
begin
  for Id in AIds do
    if (Id = '*') or SameText(Id, ARuleId) then
      Exit(True);
  Result := False;
end;

function TSuppressions.IsSuppressed(const ARuleId: string; ALine: Integer): Boolean;
var
  I: Integer;
  Entry: TSuppressionEntry;
begin
  Result := False;
  for I := 0 to FEntries.Count - 1 do
  begin
    Entry := FEntries[I];
    if ((Entry.TargetLine = -1) or (Entry.TargetLine = ALine)) and Covers(Entry.Ids, ARuleId) then
    begin
      Entry.Used := True;
      FEntries[I] := Entry;
      Result := True;
    end;
  end;
end;

function TSuppressions.Entries: TArray<TSuppressionEntry>;
begin
  Result := FEntries.ToArray;
end;

function TSuppressions.UnusedEntries: TArray<TSuppressionEntry>;
var
  Entry: TSuppressionEntry;
begin
  Result := nil;
  for Entry in FEntries do
    if not Entry.Used then
      Result := Result + [Entry];
end;

end.
