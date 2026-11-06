unit Atlas.Common.Lsp.Impact.Forms;

// Formularbindungen der Auswirkungsanalyse (#1120): Ereignis-Handler und
// Komponentennamen einer Stelle in den Formularen ihrer Unit (.dfm, .fmx).
// Die gelesenen Formulare hält TImpactFormCache für alle Läufe einer Analyse.

interface

uses
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Dfm.FormModel,
  Atlas.Common.Lsp.References;

type
  /// <summary>Bindung einer Stelle in einem Formular: Ereignis-Handler oder Komponentenname.</summary>
  TImpactFormBinding = record
    FileName: string;
    Range: TTextRange;
    /// <summary>Zeile der Formulardatei ohne Einrückung, z. B. "OnClick = Button1Click".</summary>
    Text: string;
  end;

  /// <summary>Gelesene Formulare einer oder mehrerer Analysen.</summary>
  TImpactFormCache = class
  private
    FModels: TObjectDictionary<string, TFormModel>;
    FReadText: TReferenceReadText;
    function ReadText(const AFileName: string; out AText: string): Boolean;
    function ModelOf(const AFormFile: string; out AModel: TFormModel): Boolean;
  public
    constructor Create(const AReadText: TReferenceReadText);
    destructor Destroy; override;
    /// <summary>Bindungen des Namens AName in den Formularen der Unit AFileName; leer ohne Formular.</summary>
    function Bindings(const AName, AFileName: string): TArray<TImpactFormBinding>;
    /// <summary>True für .dfm und .fmx.</summary>
    class function IsFormFile(const AFileName: string): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Dfm.FormFiles,
  Atlas.Text.Lines;

/// <summary>Bindungen an ARanges der Formulardatei AFormFile mit dem Text AText.</summary>
function BindingsIn(const AFormFile, AText: string; const ARanges: TArray<TTextRange>): TArray<TImpactFormBinding>;
var
  mLines: TArray<string>;
  mRange: TTextRange;
  mBinding: TImpactFormBinding;
begin
  Result := nil;
  mLines := TTextLines.SplitLines(AText);
  for mRange in ARanges do
  begin
    mBinding.FileName := AFormFile;
    mBinding.Range := mRange;
    mBinding.Text := '';
    if (mRange.StartPos.Line >= 0) and (mRange.StartPos.Line < Length(mLines)) then
    begin
      mBinding.Text := Trim(mLines[mRange.StartPos.Line]);
    end;
    Result := Result + [mBinding];
  end;
end;

{ TImpactFormCache }

constructor TImpactFormCache.Create(const AReadText: TReferenceReadText);
begin
  inherited Create;
  FReadText := AReadText;
  FModels := TObjectDictionary<string, TFormModel>.Create([doOwnsValues]);
end;

destructor TImpactFormCache.Destroy;
begin
  FModels.Free;
  inherited;
end;

function TImpactFormCache.ReadText(const AFileName: string; out AText: string): Boolean;
begin
  AText := '';
  Result := Assigned(FReadText) and FReadText(AFileName, AText);
end;

function TImpactFormCache.ModelOf(const AFormFile: string; out AModel: TFormModel): Boolean;
var
  mText: string;
begin
  if FModels.TryGetValue(UpperCase(AFormFile), AModel) then
  begin
    Exit(True);
  end;
  Result := ReadText(AFormFile, mText);
  if Result then
  begin
    AModel := TFormModel.Create(mText);
    FModels.Add(UpperCase(AFormFile), AModel);
  end;
end;

function TImpactFormCache.Bindings(const AName, AFileName: string): TArray<TImpactFormBinding>;
var
  mText, mFormText, mFormFile: string;
  mModel: TFormModel;
  mRanges: TArray<TTextRange>;
begin
  Result := nil;
  if (AName = '') or IsFormFile(AFileName) or not ReadText(AFileName, mText) then
  begin
    Exit;
  end;
  for mFormFile in TFormFiles.FormFiles(AFileName, mText) do
  begin
    if not ModelOf(mFormFile, mModel) then
    begin
      Continue;
    end;
    mRanges := mModel.Occurrences(AName);
    if mRanges <> nil then
    begin
      ReadText(mFormFile, mFormText);
      Result := Result + BindingsIn(mFormFile, mFormText, mRanges);
    end;
  end;
end;

class function TImpactFormCache.IsFormFile(const AFileName: string): Boolean;
begin
  Result := SameText(ExtractFileExt(AFileName), '.dfm') or SameText(ExtractFileExt(AFileName), '.fmx');
end;

end.
