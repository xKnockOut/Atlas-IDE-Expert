unit Atlas.Common.Documents.TextDocument;

// Unveränderliche Momentaufnahme eines Dokuments mit Zeilenindex.
// Zeilenumbrüche sind CRLF, LF oder CR (LSP-Spezifikation); sie gehören zur
// vorangehenden Zeile, zählen aber nicht zu ihrem Text.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract;

type
  TTextDocument = class(TInterfacedObject, ITextDocument)
  private
    FUri: string;
    FLanguageId: string;
    FVersion: Integer;
    FText: string;
    /// <summary>Offset ab 0, an dem jede Zeile beginnt; immer mindestens ein Eintrag.</summary>
    FLineStarts: TArray<Integer>;
    /// <summary>Abgeleitete Daten (Derived), erst beim ersten Zugriff angelegt; geschützt über TMonitor(Self).</summary>
    FDerived: TDictionary<string, IInterface>;
    procedure BuildLineStarts;
    /// <summary>Offset hinter dem letzten Zeichen der Zeile, ohne Zeilenumbruch.</summary>
    function LineContentEnd(ALine: Integer): Integer;
  public
    constructor Create(const AUri, ALanguageId: string; AVersion: Integer; const AText: string);
    destructor Destroy; override;
    { ITextDocument }
    function GetUri: string;
    function GetLanguageId: string;
    function GetVersion: Integer;
    function GetText: string;
    function GetLineCount: Integer;
    function LineText(ALine: Integer): string;
    function OffsetAt(const APosition: TTextPosition): Integer;
    function PositionAt(AOffset: Integer): TTextPosition;
    function ApplyChanges(const AChanges: TArray<TTextChange>; AVersion: Integer): ITextDocument;
    function Derived(const AKey: string; const AFactory: TFunc<IInterface>): IInterface;
  end;

implementation

uses
  System.Math;

{ TTextDocument }

constructor TTextDocument.Create(const AUri, ALanguageId: string; AVersion: Integer; const AText: string);
begin
  inherited Create;
  FUri := AUri;
  FLanguageId := ALanguageId;
  FVersion := AVersion;
  FText := AText;
  BuildLineStarts;
end;

procedure TTextDocument.BuildLineStarts;
var
  Starts: TArray<Integer>;
  Count: Integer;
  Len: Integer;
  Offset: Integer;

  procedure Add(AOffset: Integer);
  begin
    if Count = Length(Starts) then
      SetLength(Starts, Count * 2);
    Starts[Count] := AOffset;
    Inc(Count);
  end;

begin
  SetLength(Starts, 16);
  Count := 0;
  Add(0);
  Len := Length(FText);
  Offset := 0;
  // Offset zählt ab 0, der string ab 1: FText[Offset + 1] ist das Zeichen am Offset.
  while Offset < Len do
  begin
    case FText[Offset + 1] of
      #13:
        begin
          if (Offset + 1 < Len) and (FText[Offset + 2] = #10) then
            Inc(Offset);
          Add(Offset + 1);
        end;
      #10:
        Add(Offset + 1);
    end;
    Inc(Offset);
  end;
  SetLength(Starts, Count);
  FLineStarts := Starts;
end;

function TTextDocument.LineContentEnd(ALine: Integer): Integer;
begin
  if ALine >= High(FLineStarts) then
    Exit(Length(FText));
  Result := FLineStarts[ALine + 1];
  // Zeilenumbruch abziehen: LF, CR oder CRLF.
  if (Result > FLineStarts[ALine]) and (FText[Result] = #10) then
  begin
    Dec(Result);
    if (Result > FLineStarts[ALine]) and (FText[Result] = #13) then
      Dec(Result);
  end
  else if (Result > FLineStarts[ALine]) and (FText[Result] = #13) then
    Dec(Result);
end;

function TTextDocument.GetUri: string;
begin
  Result := FUri;
end;

function TTextDocument.GetLanguageId: string;
begin
  Result := FLanguageId;
end;

function TTextDocument.GetVersion: Integer;
begin
  Result := FVersion;
end;

function TTextDocument.GetText: string;
begin
  Result := FText;
end;

function TTextDocument.GetLineCount: Integer;
begin
  Result := Length(FLineStarts);
end;

function TTextDocument.LineText(ALine: Integer): string;
begin
  if (ALine < 0) or (ALine > High(FLineStarts)) then
    Exit('');
  Result := Copy(FText, FLineStarts[ALine] + 1, LineContentEnd(ALine) - FLineStarts[ALine]);
end;

function TTextDocument.OffsetAt(const APosition: TTextPosition): Integer;
var
  LineStart: Integer;
begin
  if APosition.Line < 0 then
    Exit(0);
  if APosition.Line > High(FLineStarts) then
    Exit(Length(FText));
  LineStart := FLineStarts[APosition.Line];
  Result := LineStart + EnsureRange(APosition.Character, 0, LineContentEnd(APosition.Line) - LineStart);
end;

function TTextDocument.PositionAt(AOffset: Integer): TTextPosition;
var
  First: Integer;
  Last: Integer;
  Middle: Integer;
begin
  AOffset := EnsureRange(AOffset, 0, Length(FText));
  // Letzte Zeile, deren Anfang nicht hinter AOffset liegt.
  First := 0;
  Last := High(FLineStarts);
  while First < Last do
  begin
    Middle := (First + Last + 1) div 2;
    if FLineStarts[Middle] <= AOffset then
      First := Middle
    else
      Last := Middle - 1;
  end;
  Result := TTextPosition.Create(First, Min(AOffset, LineContentEnd(First)) - FLineStarts[First]);
end;

destructor TTextDocument.Destroy;
begin
  FDerived.Free;
  inherited;
end;

function TTextDocument.Derived(const AKey: string; const AFactory: TFunc<IInterface>): IInterface;
begin
  // Die Sperre gilt auch während AFactory: weitere Aufrufer warten, statt selbst zu erzeugen.
  TMonitor.Enter(Self);
  try
    if (FDerived <> nil) and FDerived.TryGetValue(AKey, Result) then
      Exit;
    Result := AFactory();
    if Result <> nil then
    begin
      if FDerived = nil then
        FDerived := TDictionary<string, IInterface>.Create;
      FDerived.Add(AKey, Result);
    end;
  finally
    TMonitor.Exit(Self);
  end;
end;

function TTextDocument.ApplyChanges(const AChanges: TArray<TTextChange>; AVersion: Integer): ITextDocument;
var
  Intermediate: ITextDocument;
  Change: TTextChange;
  Text: string;
  StartOffset: Integer;
  EndOffset: Integer;
begin
  // Jede Änderung bezieht sich auf den Stand nach der vorigen. Für die erste
  // dient dieses Objekt selbst als Zeilenindex.
  Text := FText;
  Intermediate := nil;
  for Change in AChanges do
  begin
    if Change.HasRange then
    begin
      if Intermediate = nil then
      begin
        StartOffset := OffsetAt(Change.Range.StartPos);
        EndOffset := OffsetAt(Change.Range.EndPos);
      end
      else
      begin
        StartOffset := Intermediate.OffsetAt(Change.Range.StartPos);
        EndOffset := Intermediate.OffsetAt(Change.Range.EndPos);
      end;
      if EndOffset < StartOffset then
        raise EDocumentError.CreateFmt('Ungültiger Bereich in %s: Ende liegt vor dem Anfang', [FUri]);
      Text := Copy(Text, 1, StartOffset) + Change.Text + Copy(Text, EndOffset + 1, MaxInt);
    end
    else
      Text := Change.Text;
    Intermediate := TTextDocument.Create(FUri, FLanguageId, AVersion, Text);
  end;
  if Intermediate = nil then
    Intermediate := TTextDocument.Create(FUri, FLanguageId, AVersion, Text);
  Result := Intermediate;
end;

end.
