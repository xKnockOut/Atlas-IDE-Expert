unit Atlas.Common.Documents.TextDocument;

// Unveränderliche Momentaufnahme eines Dokuments mit Zeilenindex.
// Zeilenumbrüche sind CRLF, LF oder CR (LSP-Spezifikation); sie gehören zur
// vorangehenden Zeile, zählen aber nicht zu ihrem Text. Der Zeilenindex ist
// TLineTable aus Atlas.Text.Lines (gemeinsam mit dem Plugin, ADR 0012).

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Text.Lines,
  Atlas.Common.Documents.Contract;

type
  TTextDocument = class(TInterfacedObject, ITextDocument)
  private
    FUri: string;
    FLanguageId: string;
    FVersion: Integer;
    FText: string;
    /// <summary>Zeilenanfänge und -enden; immer mindestens eine Zeile.</summary>
    FLines: TLineTable;
    /// <summary>Abgeleitete Daten (Derived), erst beim ersten Zugriff angelegt; geschützt über
    /// TMonitor(Self).</summary>
    FDerived: TDictionary<string, IInterface>;
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
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TTextDocumentText = (InvalidRangeInEndLies);

const
  cTexts: array[TTextDocumentText] of TAtlasText = (
    (De: 'Ungültiger Bereich in %s: Ende liegt vor dem Anfang'; En: 'Invalid range in %s: end lies before start'));

{$SCOPEDENUMS OFF}

{ TTextDocument }

constructor TTextDocument.Create(const AUri, ALanguageId: string; AVersion: Integer; const AText: string);
begin
  inherited Create;
  FUri := AUri;
  FLanguageId := ALanguageId;
  FVersion := AVersion;
  FText := AText;
  FLines := TLineTable.Build(FText);
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
  Result := FLines.LineCount;
end;

function TTextDocument.LineText(ALine: Integer): string;
begin
  if (ALine < 0) or (ALine >= FLines.LineCount) then
  begin
    Exit('');
  end;
  Result := Copy(FText, FLines.LineStart(ALine) + 1, FLines.LineContentEnd(ALine) - FLines.LineStart(ALine));
end;

function TTextDocument.OffsetAt(const APosition: TTextPosition): Integer;
begin
  Result := FLines.OffsetAt(APosition);
end;

function TTextDocument.PositionAt(AOffset: Integer): TTextPosition;
begin
  Result := FLines.PositionAt(AOffset);
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
    begin
      Exit;
    end;
    Result := AFactory();
    if Result <> nil then
    begin
      if FDerived = nil then
      begin
        FDerived := TDictionary<string, IInterface>.Create;
      end;
      FDerived.Add(AKey, Result);
    end;
  finally
    TMonitor.Exit(Self);
  end;
end;

function TTextDocument.ApplyChanges(const AChanges: TArray<TTextChange>; AVersion: Integer): ITextDocument;
var
  mIntermediate: ITextDocument;
  mChange: TTextChange;
  mText: string;
  mStartOffset: Integer;
  mEndOffset: Integer;
begin
  // Jede Änderung bezieht sich auf den Stand nach der vorigen. Für die erste
  // dient dieses Objekt selbst als Zeilenindex.
  mText := FText;
  mIntermediate := nil;
  for mChange in AChanges do
  begin
    if mChange.HasRange then
    begin
      if mIntermediate = nil then
      begin
        mStartOffset := OffsetAt(mChange.Range.StartPos);
        mEndOffset := OffsetAt(mChange.Range.EndPos);
      end
      else
      begin
        mStartOffset := mIntermediate.OffsetAt(mChange.Range.StartPos);
        mEndOffset := mIntermediate.OffsetAt(mChange.Range.EndPos);
      end;
      if mEndOffset < mStartOffset then
      begin
        raise EDocumentError.CreateFmt(cTexts[TTextDocumentText.InvalidRangeInEndLies].Text, [FUri]);
      end;
      mText := Copy(mText, 1, mStartOffset) + mChange.Text + Copy(mText, mEndOffset + 1, MaxInt);
    end
    else
    begin
      mText := mChange.Text;
    end;
    mIntermediate := TTextDocument.Create(FUri, FLanguageId, AVersion, mText);
  end;
  if mIntermediate = nil then
  begin
    mIntermediate := TTextDocument.Create(FUri, FLanguageId, AVersion, mText);
  end;
  Result := mIntermediate;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Documents.TextDocument', cTexts);

end.
