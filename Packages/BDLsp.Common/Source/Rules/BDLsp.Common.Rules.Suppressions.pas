unit BDLsp.Common.Rules.Suppressions;

// Unterdrückung einzelner Stellen per Kommentar:
//   x := 1; // lsp-ignore: regel-a, regel-b   gilt für diese Zeile
//   // lsp-ignore: regel-a                    allein in der Zeile: gilt für die nächste Zeile
//   // lsp-ignore-file: regel-a                gilt für die ganze Datei
// "*" steht für alle Regeln. Kommentare in { } und (* *) zählen ebenso.

interface

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  BDLsp.Common.Pascal.Contract;

type
  TSuppressions = class
  private
    // Zeile (ab 0) → Regelkennungen in Kleinbuchstaben
    FLines: TObjectDictionary<Integer, TList<string>>;
    FFile: TList<string>;
    procedure AddLine(ALine: Integer; const AIds: TArray<string>);
    class function Covers(const AIds: TList<string>; const ARuleId: string): Boolean; static;
  public
    constructor Create(const ATokens: TArray<TPascalToken>);
    destructor Destroy; override;
    function IsSuppressed(const ARuleId: string; ALine: Integer): Boolean;
  end;

implementation

const
  LineMarker = 'lsp-ignore:';
  FileMarker = 'lsp-ignore-file:';

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

constructor TSuppressions.Create(const ATokens: TArray<TPascalToken>);
var
  I: Integer;
  Body, Lower: string;
  CodeBefore: Boolean;
  LastCodeLine: Integer;
begin
  inherited Create;
  FLines := TObjectDictionary<Integer, TList<string>>.Create([doOwnsValues]);
  FFile := TList<string>.Create;
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
    if StartsText(FileMarker, Lower) then
      FFile.AddRange(SplitIds(Copy(Body, Length(FileMarker) + 1, MaxInt)))
    else if StartsText(LineMarker, Lower) then
    begin
      CodeBefore := LastCodeLine = ATokens[I].StartPos.Line;
      if CodeBefore then
        AddLine(ATokens[I].StartPos.Line, SplitIds(Copy(Body, Length(LineMarker) + 1, MaxInt)))
      else
        AddLine(ATokens[I].EndPos.Line + 1, SplitIds(Copy(Body, Length(LineMarker) + 1, MaxInt)));
    end;
  end;
end;

destructor TSuppressions.Destroy;
begin
  FFile.Free;
  FLines.Free;
  inherited;
end;

procedure TSuppressions.AddLine(ALine: Integer; const AIds: TArray<string>);
var
  Ids: TList<string>;
begin
  if not FLines.TryGetValue(ALine, Ids) then
  begin
    Ids := TList<string>.Create;
    FLines.Add(ALine, Ids);
  end;
  Ids.AddRange(AIds);
end;

class function TSuppressions.Covers(const AIds: TList<string>; const ARuleId: string): Boolean;
begin
  Result := AIds.Contains('*') or AIds.Contains(LowerCase(ARuleId));
end;

function TSuppressions.IsSuppressed(const ARuleId: string; ALine: Integer): Boolean;
var
  Ids: TList<string>;
begin
  Result := Covers(FFile, ARuleId) or (FLines.TryGetValue(ALine, Ids) and Covers(Ids, ARuleId));
end;

end.
