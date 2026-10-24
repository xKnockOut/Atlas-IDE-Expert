unit Atlas.Core.Signature.Providers.Server;

// Signaturen für den Parameter-Hint (#436) vom Atlas-Server
// (textDocument/signatureHelp, #32). Query holt die Sitzung und gleicht den
// Editortext im aufrufenden Thread ab und fragt im Hintergrund; das Ergebnis
// kommt per TAtlasMainThread.Queue im Hauptthread an, aber nur für die jüngste
// Anfrage. Vor dem Freigeben der Sitzung Shutdown aufrufen (wartet auf
// laufende Anfragen). Die Sitzungsfunktion darf keinen Server starten
// (Code-Review A-01, K-03).
// Abgleich ohne Zeitlimit-Arbeiter: Sync legt die Nachricht nur in die
// Schreibwarteschlange (TLspServerProcess schreibt in einem eigenen Thread)
// und wartet nie auf den Server. Früher lief Sync mit 200 ms Zeitlimit, und
// drei Überschreitungen auf einem beschäftigten Rechner schalteten den
// Parameter-Hint ab, obwohl nichts kaputt war. Dauert der Abgleich trotzdem
// länger als TAtlasTimeLimit.LimitMs, steht das als „langsam“ im Protokoll.
// Absturzsicherheit (#493): Fehler zählt die Sicherung der Quelle
// ProviderTitle, die nach 3 Fehlern in 5 Minuten nur den Parameter-Hint
// vom Server abschaltet. Server weg bzw. dessen Zeitlimit zählt nicht.
// Platzhalter (#451): "format" der Antwort kommt nach TAtlasSignatureHelp.Format.

interface

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  System.JSON,
  System.Generics.Collections,
  Atlas.Core.Signature.Contract,
  Atlas.Core.Lsp.Session;

type
  TAtlasSignatureCallback = Atlas.Core.Signature.Contract.TAtlasSignatureCallback;

  TAtlasServerSignatureProvider = class(TInterfacedObject, IAtlasSignatureSource)
  public const
    DefaultTimeoutMs = 2000;
    ProviderTitle = 'Parameter-Hint (Server)';
  private type
    /// <summary>Hält eingereihte Aufrufe davon ab, eine freigegebene Quelle zu benutzen.</summary>
    TAliveFlag = class(TInterfacedObject)
    public
      Alive: Boolean;
    end;
  private
    FSession: TAtlasSessionFunc;
    FTimeoutMs: Cardinal;
    FLock: TCriticalSection;
    FGeneration: Integer;
    FWorkers: TList<TThread>;
    FFlag: TAliveFlag;
    FFlagRef: IInterface;
    procedure ReapWorkers;
  public
    constructor Create(const ASession: TAtlasSessionFunc; ATimeoutMs: Cardinal = DefaultTimeoutMs);
    destructor Destroy; override;
    /// <summary>Fragt die Signaturen an ALine/ACharacter (0-basiert) an; ACallback im Hauptthread.
    /// False, wenn kein Server verfügbar ist.</summary>
    function Query(const AFileName, AText: string; ALine, ACharacter: Integer;
      const ACallback: TAtlasSignatureCallback): Boolean;
    procedure Cancel;
    procedure Shutdown;
    /// <summary>Antwort auf textDocument/signatureHelp.</summary>
    class function HelpFromLsp(AResponse: TJSONValue): TAtlasSignatureHelp; static;
  end;

implementation

uses
  System.Diagnostics,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.TimeLimit,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Lsp.Client;

{ TAtlasServerSignatureProvider }

constructor TAtlasServerSignatureProvider.Create(const ASession: TAtlasSessionFunc; ATimeoutMs: Cardinal);
begin
  inherited Create;
  FSession := ASession;
  FTimeoutMs := ATimeoutMs;
  FLock := TCriticalSection.Create;
  FWorkers := TList<TThread>.Create;
  FFlag := TAliveFlag.Create;
  FFlag.Alive := True;
  FFlagRef := FFlag;
end;

destructor TAtlasServerSignatureProvider.Destroy;
begin
  Shutdown;
  // Eingereihte Aufrufe halten den Merker selbst und sehen dann Alive = False.
  FFlag.Alive := False;
  FFlagRef := nil;
  FWorkers.Free;
  FLock.Free;
  inherited;
end;

function DocumentationText(AValue: TJSONValue): string;
begin
  // string oder MarkupContent.
  if AValue is TJSONString then
    Result := TJSONString(AValue).Value
  else if AValue is TJSONObject then
    Result := TJSONObject(AValue).GetValue<string>('value', '')
  else
    Result := '';
end;

function RangeFromLsp(AValue: TJSONValue; out ARange: TAtlasFormatRange): Boolean;
begin
  ARange := Default(TAtlasFormatRange);
  Result := (AValue is TJSONObject) and TJSONObject(AValue).TryGetValue<Integer>('start.line', ARange.StartLine) and
    TJSONObject(AValue).TryGetValue<Integer>('start.character', ARange.StartCharacter) and
    TJSONObject(AValue).TryGetValue<Integer>('end.line', ARange.EndLine) and
    TJSONObject(AValue).TryGetValue<Integer>('end.character', ARange.EndCharacter);
end;

/// <summary>Objekt "format" der Antwort (#451); Found = False ohne.</summary>
function FormatFromLsp(AValue: TJSONValue): TAtlasSignatureFormat;
var
  Item, Items, Problem: TJSONValue;
  Placeholder: TAtlasFormatPlaceholder;
  Range: TAtlasFormatRange;
  Kind, TypeText: string;
begin
  Result := Default(TAtlasSignatureFormat);
  Result.ActiveArgument := -1;
  Result.ProblemPlaceholder := -1;
  Result.ProblemArgument := -1;
  if not (AValue is TJSONObject) then
    Exit;
  Result.Found := True;
  Result.FormatParameter := TJSONObject(AValue).GetValue<Integer>('formatParameter', -1);
  Result.ListParameter := TJSONObject(AValue).GetValue<Integer>('listParameter', -1);
  Result.ArgumentCount := TJSONObject(AValue).GetValue<Integer>('argumentCount', -1);
  Result.ActiveArgument := TJSONObject(AValue).GetValue<Integer>('activeArgument', -1);
  Items := TJSONObject(AValue).GetValue('placeholders');
  if Items is TJSONArray then
    for Item in TJSONArray(Items) do
      if Item is TJSONObject then
      begin
        Placeholder := Default(TAtlasFormatPlaceholder);
        Placeholder.Text := TJSONObject(Item).GetValue<string>('text', '');
        TypeText := TJSONObject(Item).GetValue<string>('type', '');
        if TypeText <> '' then
          Placeholder.TypeChar := TypeText[1];
        Placeholder.Valid := TJSONObject(Item).GetValue<Boolean>('valid', False);
        Placeholder.Argument := TJSONObject(Item).GetValue<Integer>('argument', -1);
        Placeholder.WidthArgument := TJSONObject(Item).GetValue<Integer>('width', -1);
        Placeholder.PrecisionArgument := TJSONObject(Item).GetValue<Integer>('precision', -1);
        Placeholder.HasRange := RangeFromLsp(TJSONObject(Item).GetValue('range'), Placeholder.Range);
        Result.Placeholders := Result.Placeholders + [Placeholder];
      end;
  Items := TJSONObject(AValue).GetValue('arguments');
  if Items is TJSONArray then
    for Item in TJSONArray(Items) do
    begin
      if not RangeFromLsp(Item, Range) then
        Range := Default(TAtlasFormatRange);
      Result.Arguments := Result.Arguments + [Range];
    end;
  Problem := TJSONObject(AValue).GetValue('problem');
  if Problem is TJSONObject then
  begin
    Kind := TJSONObject(Problem).GetValue<string>('kind', '');
    if Kind = 'invalid' then
      Result.Problem := TAtlasFormatProblem.Invalid
    else if Kind = 'tooManyArguments' then
      Result.Problem := TAtlasFormatProblem.TooManyArguments
    else if Kind = 'typeConflict' then
      Result.Problem := TAtlasFormatProblem.TypeConflict;
    Result.ProblemPlaceholder := TJSONObject(Problem).GetValue<Integer>('placeholder', -1);
    Result.ProblemArgument := TJSONObject(Problem).GetValue<Integer>('argument', -1);
    Result.ProblemKind := TJSONObject(Problem).GetValue<string>('argumentKind', '');
  end;
end;

class function TAtlasServerSignatureProvider.HelpFromLsp(AResponse: TJSONValue): TAtlasSignatureHelp;
var
  Signatures, Parameters, LabelValue: TJSONValue;
  Signature: TAtlasSignature;
  Parameter: TAtlasSignatureParameter;
  Item, ParameterItem, Data: TJSONValue;
  Position: Integer;
begin
  Result := Default(TAtlasSignatureHelp);
  Result.ActiveSignature := -1;
  Result.ActiveParameter := -1;
  if not (AResponse is TJSONObject) then
    Exit;
  Result.ActiveSignature := TJSONObject(AResponse).GetValue<Integer>('activeSignature', -1);
  Result.ActiveParameter := TJSONObject(AResponse).GetValue<Integer>('activeParameter', -1);
  Result.Format := FormatFromLsp(TJSONObject(AResponse).GetValue('format'));
  Signatures := TJSONObject(AResponse).GetValue('signatures');
  if not (Signatures is TJSONArray) then
    Exit;
  for Item in TJSONArray(Signatures) do
  begin
    if not (Item is TJSONObject) then
      Continue;
    Signature := Default(TAtlasSignature);
    Signature.Label_ := TJSONObject(Item).GetValue<string>('label', '');
    Signature.Documentation := DocumentationText(TJSONObject(Item).GetValue('documentation'));
    // Argumenttypen (#498): data.fits = false dämpft die Überladung.
    Data := TJSONObject(Item).GetValue('data');
    if (Data is TJSONObject) and (TJSONObject(Data).GetValue('fits') is TJSONBool) and
      not TJSONBool(TJSONObject(Data).GetValue('fits')).AsBoolean then
    begin
      Signature.TypeMismatch := True;
      Signature.MismatchArgument := TJSONObject(Data).GetValue<Integer>('mismatch', 0);
    end;
    Parameters := TJSONObject(Item).GetValue('parameters');
    if Parameters is TJSONArray then
      for ParameterItem in TJSONArray(Parameters) do
      begin
        if not (ParameterItem is TJSONObject) then
          Continue;
        Parameter := Default(TAtlasSignatureParameter);
        Parameter.Start := -1;
        Parameter.Stop := -1;
        // label: [Start, Ende] im Signaturtext oder der Text selbst.
        LabelValue := TJSONObject(ParameterItem).GetValue('label');
        if (LabelValue is TJSONArray) and (TJSONArray(LabelValue).Count = 2) and
          (TJSONArray(LabelValue).Items[0] is TJSONNumber) and (TJSONArray(LabelValue).Items[1] is TJSONNumber) then
        begin
          Parameter.Start := TJSONNumber(TJSONArray(LabelValue).Items[0]).AsInt;
          Parameter.Stop := TJSONNumber(TJSONArray(LabelValue).Items[1]).AsInt;
        end
        else if LabelValue is TJSONString then
        begin
          Position := Pos(TJSONString(LabelValue).Value, Signature.Label_);
          if Position > 0 then
          begin
            Parameter.Start := Position - 1;
            Parameter.Stop := Parameter.Start + Length(TJSONString(LabelValue).Value);
          end;
        end;
        Parameter.Documentation := DocumentationText(TJSONObject(ParameterItem).GetValue('documentation'));
        Signature.Parameters := Signature.Parameters + [Parameter];
      end;
    Result.Signatures := Result.Signatures + [Signature];
  end;
end;

procedure TAtlasServerSignatureProvider.ReapWorkers;
var
  Index: Integer;
begin
  FLock.Enter;
  try
    for Index := FWorkers.Count - 1 downto 0 do
      if FWorkers[Index].Finished then
      begin
        FWorkers[Index].Free;
        FWorkers.Delete(Index);
      end;
  finally
    FLock.Leave;
  end;
end;

procedure TAtlasServerSignatureProvider.Cancel;
begin
  TInterlocked.Increment(FGeneration);
end;

procedure TAtlasServerSignatureProvider.Shutdown;
var
  Workers: TArray<TThread>;
  Worker: TThread;
begin
  Cancel;
  FLock.Enter;
  try
    Workers := FWorkers.ToArray;
    FWorkers.Clear;
  finally
    FLock.Leave;
  end;
  for Worker in Workers do
  begin
    Worker.WaitFor;
    Worker.Free;
  end;
end;

function TAtlasServerSignatureProvider.Query(const AFileName, AText: string; ALine, ACharacter: Integer;
  const ACallback: TAtlasSignatureCallback): Boolean;
var
  Session: TLspSession;
  Generation: Integer;
  FileName: string;
  Worker: TThread;
  Provider: TAtlasServerSignatureProvider;
  Flag: TAliveFlag;
  FlagRef: IInterface;
  Watch: TStopwatch;
begin
  Generation := TInterlocked.Increment(FGeneration);
  ReapWorkers;
  Result := False;
  if (AFileName = '') or TAtlasGuard.ProviderDisabled(ProviderTitle) then
    Exit;
  FileName := AFileName;
  // Sitzung holen und abgleichen im aufrufenden Thread: Sync wartet nicht auf den Server (siehe oben).
  Session := nil;
  Watch := TStopwatch.StartNew;
  try
    if Assigned(FSession) then
      Session := FSession();
    if Session <> nil then
      Session.Sync(FileName, AText);
  except
    // Server weg: kein Hint. Anderes zählt die Sicherung (#493).
    on E: Exception do
    begin
      if not (E is ELspClientError) then
        TAtlasGuard.ReportProvider(ProviderTitle, E);
      Exit;
    end;
  end;
  if Watch.ElapsedMilliseconds > TAtlasTimeLimit.LimitMs then
    TAtlasGuard.ReportProviderSlow(ProviderTitle, Format('Abgleich dauerte %d ms', [Watch.ElapsedMilliseconds]));
  Result := Session <> nil;
  if not Result then
    Exit;
  Provider := Self;
  Flag := FFlag;
  FlagRef := FFlagRef;
  Worker := TThread.CreateAnonymousThread(
    procedure
    var
      Response: TJSONValue;
      Help: TAtlasSignatureHelp;
    begin
      Help := Default(TAtlasSignatureHelp);
      try
        Response := Session.SignatureHelp(FileName, ALine, ACharacter, Provider.FTimeoutMs);
        try
          Help := HelpFromLsp(Response);
        finally
          Response.Free;
        end;
      except
        // Server weg oder Zeitlimit: kein Hint. Anderes zählt die Sicherung (#493).
        on E: Exception do
        begin
          Help := Default(TAtlasSignatureHelp);
          if not (E is ELspClientError) then
            TAtlasGuard.ReportProvider(ProviderTitle, E);
        end;
      end;
      if TInterlocked.CompareExchange(Provider.FGeneration, 0, 0) <> Generation then
        Exit;
      // Im Hauptthread erst prüfen, ob die Quelle noch lebt und dies die jüngste Anfrage ist.
      TAtlasMainThread.Queue(TAtlasFeature.Signature,
        procedure
        begin
          if Flag.Alive and (FlagRef <> nil) and
            (TInterlocked.CompareExchange(Provider.FGeneration, 0, 0) = Generation) then
            TAtlasGuard.Run(TAtlasFeature.Signature,
              procedure
              begin
                ACallback(Help);
              end);
        end);
    end);
  Worker.FreeOnTerminate := False;
  FLock.Enter;
  try
    FWorkers.Add(Worker);
  finally
    FLock.Leave;
  end;
  Worker.Start;
end;

end.
