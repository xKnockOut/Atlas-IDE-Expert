unit Atlas.Core.Debug.AccessViolation;

// Zugriffsverletzung erklären (#865), ohne VCL und Open Tools API:
//   - TAtlasAvMessage liest aus Klasse und Meldung, ob es eine Zugriffsverletzung ist, und die Adresse, auf die
//     zugegriffen wurde („Lesen von Adresse 0000001C“, „Read of address 0000001C“, auch Schreiben und
//     Ausführen, 8 oder 16 Stellen).
//   - Zugriffsketten der Anweisung am Halt kommen von atlas/accessChains (Atlas.Core.Lsp.AccessChains).
//   - TAtlasAvAnalysis führt die Auswertung als Folge von Anfragen an den Debugger: Glieder jeder Kette von
//     links als Pointer(Ausdruck); das erste nil-Glied beendet die Kette. Ein Wert aus einem Füllmuster des
//     Speichermanagers ($80808080 FastMM, $FEEEFEEE Windows-Heap) heißt „freigegeben“, ein Wert unter $10000
//     „zeigt ins Leere“. Ohne nil prüft Atlas den Kopf jedes Objekts auf ein Füllmuster: das erste Wort (VMT-Zeiger,
//     Windows-Heap) und, wenn es keines trägt, das zweite (FastMM FullDebugMode ersetzt den VMT-Zeiger durch den
//     von TFreedObject und füllt den Rest), und bei
//     dynamischen Arrays den Index gegen Length. Glieder, die etwas aufrufen, bleiben ohne AAllowCalls
//     „nicht ausgewertet“. Zum nil-Glied einer Klasse sucht Atlas das Feld, dessen Versatz die Adresse ist:
//     geschätzt vom Server, nachgeprüft über NativeInt(@TKlasse(nil).FFeld).
//   - Ergebnis: genau eine Ursache, sonst „nicht eindeutig“ mit allen geprüften Gliedern.

interface

uses
  System.SysUtils,
  Atlas.Core.Lsp.AccessChains;

type
  {$SCOPEDENUMS ON}
  TAtlasAvOperation = (Unknown, Read, Write, Execute);
  TAtlasAvCheckState = (Pending, Ok, NilValue, Freed, Invalid, OutOfRange, NotEvaluated, NotReached, Failed);
  TAtlasAvVerdictKind = (None, NilLink, Freed, FreedMemory, Invalid, OutOfRange, Ambiguous);
  TAtlasAvPurpose = (Value, PlainValue, Length, Index, Header, Offset);
  {$SCOPEDENUMS OFF}

  TAtlasAvMessage = record
    IsAccessViolation: Boolean;
    AddressKnown: Boolean;
    Operation: TAtlasAvOperation;
    /// <summary>Adresse, auf die zugegriffen wurde.</summary>
    Address: UInt64;
    /// <summary>Klasse EAccessViolation oder EExternalException bzw. ein Meldungstext einer Zugriffsverletzung.
    /// </summary>
    class function Parse(const AClassName, AMessage: string): TAtlasAvMessage; static;
  end;

  TAtlasAvCheck = record
    Chain: Integer;
    Link: Integer;
    Expression: string;
    State: TAtlasAvCheckState;
    /// <summary>Gelesener Wert ($1C, Länge 5 / Index 7) für die Liste.</summary>
    Value: string;
  end;

  TAtlasAvRequest = record
    Expression: string;
    Purpose: TAtlasAvPurpose;
    /// <summary>Darf die Auswertung etwas aufrufen (allowCalls)?</summary>
    SideEffects: Boolean;
  end;

  TAtlasAvVerdict = record
    Kind: TAtlasAvVerdictKind;
    HasCulprit: Boolean;
    Culprit: TAtlasAvLink;
    /// <summary>Wert des Glieds (bei Invalid und Freed) bzw. die Adresse bei FreedMemory.</summary>
    Value: UInt64;
    /// <summary>Feld am Versatz der Adresse; '' ohne.</summary>
    Field: string;
    FieldOffset: Integer;
    /// <summary>Versatz vom Debugger bestätigt; sonst geschätzt.</summary>
    FieldExact: Boolean;
    /// <summary>Adresse 0 bei einer Klasse oder einem Interface: Zugriff auf die VMT.</summary>
    VmtAccess: Boolean;
    Index: Int64;
    Length: Int64;
    /// <summary>Anzahl gefundener Ursachen (bei Ambiguous mehr als eine oder keine).</summary>
    Causes: Integer;
  end;

  TAtlasAvAnalysis = class
  public const
    /// <summary>Darunter zeigt ein Zeiger ins Leere (erste Seite des Adressraums).</summary>
    cNearNil = $10000;
    cMaxOffsetChecks = 32;
  private type
    {$SCOPEDENUMS ON}
    TPhase = (Links, Headers, Offsets, Done);
    {$SCOPEDENUMS OFF}
    /// <summary>Gelesenes zu einer Prüfung (Index wie Checks).</summary>
    TCheckData = record
      Value: UInt64;
      Known: Boolean;
      /// <summary>Länge des dynamischen Arrays, wenn ein Index geprüft wird.</summary>
      Length: Int64;
    end;
    /// <summary>Suche des Felds an der Adresse eines nil-Zugriffs.</summary>
    TOffsetSearch = record
      Candidates: TArray<Integer>;
      Next: Integer;
      /// <summary>Feld, dessen geschätzter Versatz zur Adresse passt; -1 ohne.</summary>
      Estimate: Integer;
    end;
  private
    FChains: TAtlasAvChains;
    FMessage: TAtlasAvMessage;
    FPointerSize: Integer;
    FAllowCalls: Boolean;
    FChecks: TArray<TAtlasAvCheck>;
    FPhase: TPhase;
    FCheck: Integer;
    /// <summary>Kopf: 0 = erstes Wort gefragt, 1 = zweites.</summary>
    FHeaderWord: Integer;
    FPending: TAtlasAvRequest;
    FHasPending: Boolean;
    FData: TArray<TCheckData>;
    FCauses: TArray<Integer>;
    FVerdict: TAtlasAvVerdict;
    FOffsets: TOffsetSearch;
    procedure SkipRestOfChain(ACheck: Integer; AState: TAtlasAvCheckState);
    function NextLinkRequest(out ARequest: TAtlasAvRequest): Boolean;
    function NextHeaderRequest(out ARequest: TAtlasAvRequest): Boolean;
    function NextOffsetRequest(out ARequest: TAtlasAvRequest): Boolean;
    procedure Ask(const AExpression: string; APurpose: TAtlasAvPurpose);
    /// <summary>Antwort auf den Wert eines Glieds; True, wenn eine Folgefrage gestellt ist.</summary>
    function AnswerValue(AOk: Boolean; const AText: string; const ALink: TAtlasAvLink): Boolean;
    procedure AnswerIndex(AOk: Boolean; const AText: string; const ALink: TAtlasAvLink);
    procedure AnswerLink(AOk: Boolean; const AText: string);
    /// <summary>Frage der aktuellen Phase; False wechselt die Phase.</summary>
    function PhaseRequest(out ARequest: TAtlasAvRequest): Boolean;
    procedure AnswerHeader(AOk: Boolean; const AText: string);
    procedure AnswerOffset(AOk: Boolean; const AText: string);
    procedure AddCause(ACheck: Integer);
    procedure StartOffsets;
    procedure Finish;
  public
    constructor Create(const AChains: TAtlasAvChains; const AMessage: TAtlasAvMessage; APointerSize: Integer;
      AAllowCalls: Boolean);
    /// <summary>Nächste Frage an den Debugger; False, wenn die Analyse fertig ist.</summary>
    function Next(out ARequest: TAtlasAvRequest): Boolean;
    /// <summary>Antwort auf die letzte Frage; AOk = False bei Fehler der Auswertung.</summary>
    procedure Answer(AOk: Boolean; const AText: string);
    /// <summary>Abbrechen (weitergelaufen): Offenes bleibt „nicht ausgewertet“, das Ergebnis steht fest.</summary>
    procedure Abort;
    function Done: Boolean;
    function Verdict: TAtlasAvVerdict;
    /// <summary>Glied zur Prüfung ACheck (Index in Checks).</summary>
    function LinkOf(ACheck: Integer): TAtlasAvLink;
    property Checks: TArray<TAtlasAvCheck> read FChecks;
    property Chains: TAtlasAvChains read FChains;
    property AllowCalls: Boolean read FAllowCalls;
    property AccessMessage: TAtlasAvMessage read FMessage;
  end;

  /// <summary>Werte des Debuggers lesen und deuten (für TAtlasAvAnalysis und die Anzeige).</summary>
  TAtlasAvValues = record
  public
    /// <summary>Adresse aus 'nil', '$1C', '0x1c', '28' bzw. '($1C)'; False sonst.</summary>
    class function ParseAddress(const AText: string; out AValue: UInt64): Boolean; static;
    class function ParseInteger(const AText: string; out AValue: Int64): Boolean; static;
    /// <summary>Füllmuster freigegebenen Speichers ($80808080, $FEEEFEEE, je nach Zeigergröße).</summary>
    class function IsFreedPattern(AValue: UInt64; APointerSize: Integer): Boolean; static;
    /// <summary>Liegt AValue nahe hinter einem Füllmuster (Feld eines freigegebenen Objekts)?</summary>
    class function NearFreedPattern(AValue: UInt64; APointerSize: Integer): Boolean; static;
    class function HexText(AValue: UInt64): string; static;
  end;

implementation

uses
  System.Math,
  System.StrUtils;

const
  cFreedPatterns32: array[0..2] of UInt64 = ($80808080, $FEEEFEEE, $DDDDDDDD);
  cFreedPatterns64: array[0..2] of UInt64 = ($8080808080808080, $FEEEFEEEFEEEFEEE, $DDDDDDDDDDDDDDDD);

function LowerTrim(const AText: string): string;
begin
  Result := LowerCase(Trim(AText));
end;

/// <summary>Hexzahl ab APos (Leerzeichen davor erlaubt); False ohne Ziffer.</summary>
function ReadHex(const AText: string; APos: Integer; out AValue: UInt64): Boolean;
var
  mDigits: Integer;
  mCh: Char;
begin
  AValue := 0;
  mDigits := 0;
  while (APos <= Length(AText)) and (AText[APos] = ' ') do
  begin
    Inc(APos);
  end;
  if (APos <= Length(AText)) and (AText[APos] = '$') then
  begin
    Inc(APos);
  end;
  while (APos <= Length(AText)) and (mDigits < 16) do
  begin
    mCh := AText[APos];
    if CharInSet(mCh, ['0'..'9']) then
    begin
      AValue := AValue * 16 + UInt64(Ord(mCh) - Ord('0'));
    end
    else if CharInSet(mCh, ['a'..'f']) then
    begin
      AValue := AValue * 16 + UInt64(Ord(mCh) - Ord('a') + 10);
    end
    else if CharInSet(mCh, ['A'..'F']) then
    begin
      AValue := AValue * 16 + UInt64(Ord(mCh) - Ord('A') + 10);
    end
    else
    begin
      Break;
    end;
    Inc(mDigits);
    Inc(APos);
  end;
  Result := mDigits > 0;
end;

{ TAtlasAvMessage }

class function TAtlasAvMessage.Parse(const AClassName, AMessage: string): TAtlasAvMessage;
const
  // Wörter vor der Zieladresse, deutsch und englisch; die Adresse des Codes steht davor ("bei Adresse").
  cOperations: array[0..5] of string = ('lesen von adresse', 'schreiben von adresse', 'ausführung von adresse',
    'read of address', 'write of address', 'execution of address');
  cKinds: array[0..5] of TAtlasAvOperation = (TAtlasAvOperation.Read, TAtlasAvOperation.Write,
    TAtlasAvOperation.Execute, TAtlasAvOperation.Read, TAtlasAvOperation.Write, TAtlasAvOperation.Execute);
var
  mText, mClassName_: string;
  mIndex, mAt: Integer;
  mValue: UInt64;
begin
  Result := Default(TAtlasAvMessage);
  mText := LowerCase(AMessage);
  mClassName_ := LowerTrim(AClassName);
  Result.IsAccessViolation := (mClassName_ = 'eaccessviolation') or (Pos('zugriffsverletzung', mText) > 0) or
    (Pos('access violation', mText) > 0);
  // EExternalException trägt nur mit passender Meldung eine Zugriffsverletzung (C0000005).
  if (mClassName_ = 'eexternalexception') and not Result.IsAccessViolation then
  begin
    Result.IsAccessViolation := Pos('c0000005', mText) > 0;
  end;
  if not Result.IsAccessViolation then
  begin
    Exit;
  end;
  for mIndex := Low(cOperations) to High(cOperations) do
  begin
    mAt := Pos(cOperations[mIndex], mText);
    if (mAt > 0) and ReadHex(AMessage, mAt + Length(cOperations[mIndex]), mValue) then
    begin
      Result.AddressKnown := True;
      Result.Address := mValue;
      Result.Operation := cKinds[mIndex];
      Exit;
    end;
  end;
end;

{ TAtlasAvAnalysis }

constructor TAtlasAvAnalysis.Create(const AChains: TAtlasAvChains; const AMessage: TAtlasAvMessage;
  APointerSize: Integer; AAllowCalls: Boolean);
var
  mChainIndex, mLinkIndex: Integer;
  mCheck: TAtlasAvCheck;
begin
  inherited Create;
  FChains := AChains;
  FMessage := AMessage;
  FPointerSize := APointerSize;
  FAllowCalls := AAllowCalls;
  for mChainIndex := 0 to High(FChains.Chains) do
  begin
    for mLinkIndex := 0 to High(FChains.Chains[mChainIndex].Links) do
    begin
      mCheck := Default(TAtlasAvCheck);
      mCheck.Chain := mChainIndex;
      mCheck.Link := mLinkIndex;
      mCheck.Expression := FChains.Chains[mChainIndex].Links[mLinkIndex].Expression;
      FChecks := FChecks + [mCheck];
    end;
  end;
  SetLength(FData, Length(FChecks));
  FPhase := TPhase.Links;
  FCheck := 0;
end;

class function TAtlasAvValues.HexText(AValue: UInt64): string;
begin
  if AValue <= $FFFFFFFF then
  begin
    Result := '$' + IntToHex(AValue, 8);
  end
  else
  begin
    Result := '$' + IntToHex(AValue, 16);
  end;
end;

class function TAtlasAvValues.ParseAddress(const AText: string; out AValue: UInt64): Boolean;
var
  mText: string;
  mSigned: Int64;
begin
  AValue := 0;
  mText := Trim(AText);
  // Typumwandlungen zeigt der Debugger mitunter eingeklammert.
  if (Length(mText) > 2) and (mText[1] = '(') and (mText[Length(mText)] = ')') then
  begin
    mText := Trim(Copy(mText, 2, Length(mText) - 2));
  end;
  if SameText(mText, 'nil') then
  begin
    Exit(True);
  end;
  if mText = '' then
  begin
    Exit(False);
  end;
  if mText[1] = '$' then
  begin
    Exit(ReadHex(mText, 1, AValue) and (Length(mText) <= 17));
  end;
  if StartsText('0x', mText) then
  begin
    Exit(ReadHex(mText, 3, AValue) and (Length(mText) <= 18));
  end;
  Result := TryStrToInt64(mText, mSigned);
  if Result then
  begin
    AValue := UInt64(mSigned);
  end
  else
  begin
    // Dezimal über Int64 hinaus (Füllmuster unter Win64 als Zahl).
    Result := TryStrToUInt64(mText, AValue);
  end;
end;

class function TAtlasAvValues.ParseInteger(const AText: string; out AValue: Int64): Boolean;
var
  mAddress: UInt64;
begin
  Result := TryStrToInt64(Trim(AText), AValue);
  if not Result and TAtlasAvValues.ParseAddress(AText, mAddress) then
  begin
    AValue := Int64(mAddress);
    Result := True;
  end;
end;

class function TAtlasAvValues.IsFreedPattern(AValue: UInt64; APointerSize: Integer): Boolean;
var
  mPattern: UInt64;
begin
  if APointerSize = 8 then
  begin
    for mPattern in cFreedPatterns64 do
    begin
      if AValue = mPattern then
      begin
        Exit(True);
      end;
    end;
  end;
  // Auch unter Win64 stehen in 32-Bit-Feldern die kurzen Muster.
  for mPattern in cFreedPatterns32 do
  begin
    if AValue = mPattern then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TAtlasAvValues.NearFreedPattern(AValue: UInt64; APointerSize: Integer): Boolean;
var
  mPattern: UInt64;
begin
  for mPattern in cFreedPatterns32 do
  begin
    if (AValue >= mPattern) and (AValue - mPattern < TAtlasAvAnalysis.cNearNil) then
    begin
      Exit(True);
    end;
  end;
  if APointerSize = 8 then
  begin
    for mPattern in cFreedPatterns64 do
    begin
      if (AValue >= mPattern) and (AValue - mPattern < TAtlasAvAnalysis.cNearNil) then
      begin
        Exit(True);
      end;
    end;
  end;
  Result := False;
end;

function TAtlasAvAnalysis.LinkOf(ACheck: Integer): TAtlasAvLink;
begin
  Result := FChains.Chains[FChecks[ACheck].Chain].Links[FChecks[ACheck].Link];
end;

procedure TAtlasAvAnalysis.SkipRestOfChain(ACheck: Integer; AState: TAtlasAvCheckState);
var
  mIndex: Integer;
begin
  mIndex := ACheck + 1;
  while (mIndex <= High(FChecks)) and (FChecks[mIndex].Chain = FChecks[ACheck].Chain) do
  begin
    if FChecks[mIndex].State = TAtlasAvCheckState.Pending then
    begin
      FChecks[mIndex].State := AState;
    end;
    Inc(mIndex);
  end;
end;

procedure TAtlasAvAnalysis.AddCause(ACheck: Integer);
begin
  FCauses := FCauses + [ACheck];
end;

function TAtlasAvAnalysis.Done: Boolean;
begin
  Result := FPhase = TPhase.Done;
end;

function TAtlasAvAnalysis.NextLinkRequest(out ARequest: TAtlasAvRequest): Boolean;
var
  mLink: TAtlasAvLink;
begin
  Result := False;
  while FCheck <= High(FChecks) do
  begin
    if FChecks[FCheck].State <> TAtlasAvCheckState.Pending then
    begin
      Inc(FCheck);
      Continue;
    end;
    mLink := LinkOf(FCheck);
    if mLink.Call and not FAllowCalls then
    begin
      // Getter oder Funktion: ohne allowCalls nichts ausführen, auch nichts dahinter.
      FChecks[FCheck].State := TAtlasAvCheckState.NotEvaluated;
      SkipRestOfChain(FCheck, TAtlasAvCheckState.NotEvaluated);
      Inc(FCheck);
      Continue;
    end;
    ARequest := Default(TAtlasAvRequest);
    ARequest.Expression := 'Pointer(' + mLink.Expression + ')';
    ARequest.Purpose := TAtlasAvPurpose.Value;
    ARequest.SideEffects := mLink.Call;
    Exit(True);
  end;
end;

/// <summary>Zustand eines gelesenen Zeigerwerts.</summary>
function ValueState(AValue: UInt64; APointerSize: Integer): TAtlasAvCheckState;
begin
  if AValue = 0 then
  begin
    Result := TAtlasAvCheckState.NilValue;
  end
  else if TAtlasAvValues.IsFreedPattern(AValue, APointerSize) then
  begin
    Result := TAtlasAvCheckState.Freed;
  end
  else if AValue < TAtlasAvAnalysis.cNearNil then
  begin
    Result := TAtlasAvCheckState.Invalid;
  end
  else
  begin
    Result := TAtlasAvCheckState.Ok;
  end;
end;

procedure TAtlasAvAnalysis.Ask(const AExpression: string; APurpose: TAtlasAvPurpose);
begin
  FPending.Expression := AExpression;
  FPending.Purpose := APurpose;
  FHasPending := True;
end;

function TAtlasAvAnalysis.AnswerValue(AOk: Boolean; const AText: string; const ALink: TAtlasAvLink): Boolean;
var
  mValue: UInt64;
begin
  Result := False;
  if AOk and TAtlasAvValues.ParseAddress(AText, mValue) then
  begin
    FData[FCheck].Value := mValue;
    FData[FCheck].Known := True;
    FChecks[FCheck].State := ValueState(mValue, FPointerSize);
    FChecks[FCheck].Value := TAtlasAvValues.HexText(mValue);
  end
  else if FPending.Purpose = TAtlasAvPurpose.Value then
  begin
    // Die Umwandlung kennt nicht jeder Debugger: den Ausdruck selbst fragen.
    Ask(ALink.Expression, TAtlasAvPurpose.PlainValue);
    Exit(True);
  end
  else if AOk then
  begin
    FChecks[FCheck].State := TAtlasAvCheckState.Ok;
    FChecks[FCheck].Value := AText;
  end
  else
  begin
    FChecks[FCheck].State := TAtlasAvCheckState.Failed;
  end;
  if FChecks[FCheck].State in [TAtlasAvCheckState.NilValue, TAtlasAvCheckState.Freed,
    TAtlasAvCheckState.Invalid] then
  begin
    AddCause(FCheck);
    SkipRestOfChain(FCheck, TAtlasAvCheckState.NotReached);
  end
  else if (FChecks[FCheck].State = TAtlasAvCheckState.Ok) and (ALink.Kind = TAtlasAvLinkKind.DynArray) and
    (ALink.IndexText <> '') and ALink.IndexPlain then
  begin
    Ask('Length(' + ALink.Expression + ')', TAtlasAvPurpose.Length);
    FPending.SideEffects := False;
    Result := True;
  end;
end;

procedure TAtlasAvAnalysis.AnswerIndex(AOk: Boolean; const AText: string; const ALink: TAtlasAvLink);
var
  mNumber: Int64;
begin
  if not (AOk and TAtlasAvValues.ParseInteger(AText, mNumber)) then
  begin
    Exit;
  end;
  FChecks[FCheck].Value := Format('%s · %s = %d / %d', [FChecks[FCheck].Value, ALink.IndexText, mNumber,
    FData[FCheck].Length]);
  if (mNumber < 0) or (mNumber >= FData[FCheck].Length) then
  begin
    FChecks[FCheck].State := TAtlasAvCheckState.OutOfRange;
    FData[FCheck].Value := UInt64(mNumber);
    AddCause(FCheck);
    SkipRestOfChain(FCheck, TAtlasAvCheckState.NotReached);
  end;
end;

procedure TAtlasAvAnalysis.AnswerLink(AOk: Boolean; const AText: string);
var
  mLink: TAtlasAvLink;
  mNumber: Int64;
  mAsked: Boolean;
begin
  mLink := LinkOf(FCheck);
  mAsked := False;
  case FPending.Purpose of
    TAtlasAvPurpose.Value, TAtlasAvPurpose.PlainValue:
      mAsked := AnswerValue(AOk, AText, mLink);
    TAtlasAvPurpose.Length:
      begin
        mAsked := AOk and TAtlasAvValues.ParseInteger(AText, mNumber);
        if mAsked then
        begin
          FData[FCheck].Length := mNumber;
          Ask(mLink.IndexText, TAtlasAvPurpose.Index);
        end;
      end;
    TAtlasAvPurpose.Index:
      AnswerIndex(AOk, AText, mLink);
    TAtlasAvPurpose.Header, TAtlasAvPurpose.Offset: ;
  end;
  if not mAsked then
  begin
    Inc(FCheck);
  end;
end;

function TAtlasAvAnalysis.NextHeaderRequest(out ARequest: TAtlasAvRequest): Boolean;
var
  mLink: TAtlasAvLink;
begin
  Result := False;
  while FCheck <= High(FChecks) do
  begin
    mLink := LinkOf(FCheck);
    if (FChecks[FCheck].State = TAtlasAvCheckState.Ok) and FData[FCheck].Known and
      (mLink.Kind = TAtlasAvLinkKind.ClassRef) then
    begin
      ARequest := Default(TAtlasAvRequest);
      // Erstes Wort der Instanz (VMT-Zeiger) bzw. das zweite; nach der Freigabe das Füllmuster.
      ARequest.Expression := 'PNativeUInt(' +
        TAtlasAvValues.HexText(FData[FCheck].Value + UInt64(FHeaderWord * FPointerSize)) + ')^';
      ARequest.Purpose := TAtlasAvPurpose.Header;
      Exit(True);
    end;
    Inc(FCheck);
  end;
end;

procedure TAtlasAvAnalysis.AnswerHeader(AOk: Boolean; const AText: string);
var
  mValue: UInt64;
begin
  if AOk and TAtlasAvValues.ParseAddress(AText, mValue) and TAtlasAvValues.IsFreedPattern(mValue, FPointerSize) then
  begin
    FChecks[FCheck].State := TAtlasAvCheckState.Freed;
    AddCause(FCheck);
    SkipRestOfChain(FCheck, TAtlasAvCheckState.NotReached);
  end
  else if AOk and (FHeaderWord = 0) then
  begin
    // Das zweite Wort fragen (FastMM FullDebugMode).
    FHeaderWord := 1;
    Exit;
  end;
  FHeaderWord := 0;
  Inc(FCheck);
end;

procedure TAtlasAvAnalysis.StartOffsets;
var
  mLink: TAtlasAvLink;
  mIndex: Integer;
begin
  FOffsets.Candidates := nil;
  FOffsets.Next := 0;
  FOffsets.Estimate := -1;
  if (Length(FCauses) <> 1) or (FChecks[FCauses[0]].State <> TAtlasAvCheckState.NilValue) or
    not FMessage.AddressKnown or (FMessage.Address >= cNearNil) then
  begin
    Exit;
  end;
  mLink := LinkOf(FCauses[0]);
  if not (mLink.Kind in [TAtlasAvLinkKind.ClassRef, TAtlasAvLinkKind.InterfaceRef]) then
  begin
    Exit;
  end;
  if (FMessage.Address = 0) or (mLink.Kind = TAtlasAvLinkKind.InterfaceRef) then
  begin
    Exit;
  end;
  // Geschätzter Treffer zuerst prüfen, dann alle Felder der Reihe nach.
  for mIndex := 0 to High(mLink.Fields) do
  begin
    if mLink.Fields[mIndex].Offset = Integer(FMessage.Address) then
    begin
      FOffsets.Estimate := mIndex;
    end;
  end;
  if FOffsets.Estimate >= 0 then
  begin
    FOffsets.Candidates := FOffsets.Candidates + [FOffsets.Estimate];
  end;
  for mIndex := 0 to Min(High(mLink.Fields), cMaxOffsetChecks - 1) do
  begin
    if mIndex <> FOffsets.Estimate then
    begin
      FOffsets.Candidates := FOffsets.Candidates + [mIndex];
    end;
  end;
end;

function TAtlasAvAnalysis.NextOffsetRequest(out ARequest: TAtlasAvRequest): Boolean;
var
  mLink: TAtlasAvLink;
begin
  Result := False;
  if FOffsets.Next > High(FOffsets.Candidates) then
  begin
    // Alle Felder nachgefragt, keines liegt an der Adresse: Die Schätzung ist widerlegt.
    if FOffsets.Candidates <> nil then
    begin
      FOffsets.Estimate := -1;
    end;
    FOffsets.Candidates := nil;
    Exit;
  end;
  mLink := LinkOf(FCauses[0]);
  ARequest := Default(TAtlasAvRequest);
  ARequest.Expression := 'NativeInt(@' + mLink.TypeName + '(nil).' +
    mLink.Fields[FOffsets.Candidates[FOffsets.Next]].Name + ')';
  ARequest.Purpose := TAtlasAvPurpose.Offset;
  Result := True;
end;

procedure TAtlasAvAnalysis.AnswerOffset(AOk: Boolean; const AText: string);
var
  mNumber: Int64;
  mLink: TAtlasAvLink;
begin
  mLink := LinkOf(FCauses[0]);
  if not (AOk and TAtlasAvValues.ParseInteger(AText, mNumber)) then
  begin
    // Der Debugger kann den Versatz nicht ausrechnen: bei der Schätzung bleiben.
    if FOffsets.Estimate >= 0 then
    begin
      FVerdict.Field := mLink.Fields[FOffsets.Estimate].Name;
      FVerdict.FieldOffset := mLink.Fields[FOffsets.Estimate].Offset;
      FVerdict.FieldExact := False;
    end;
    FOffsets.Candidates := nil;
    Exit;
  end;
  if UInt64(mNumber) = FMessage.Address then
  begin
    FVerdict.Field := mLink.Fields[FOffsets.Candidates[FOffsets.Next]].Name;
    FVerdict.FieldOffset := Integer(mNumber);
    FVerdict.FieldExact := True;
    FOffsets.Candidates := nil;
    Exit;
  end;
  Inc(FOffsets.Next);
end;

function TAtlasAvAnalysis.PhaseRequest(out ARequest: TAtlasAvRequest): Boolean;
begin
  Result := False;
  case FPhase of
    TPhase.Links:
      begin
        Result := NextLinkRequest(ARequest);
        if not Result then
        begin
          FCheck := 0;
          // Ohne nil: freigegebene Objekte am Kopf erkennen.
          FPhase := TPhase.Headers;
          if FCauses <> nil then
          begin
            FPhase := TPhase.Offsets;
            StartOffsets;
          end;
        end;
      end;
    TPhase.Headers:
      begin
        Result := (FCauses = nil) and NextHeaderRequest(ARequest);
        if not Result then
        begin
          FPhase := TPhase.Offsets;
          StartOffsets;
        end;
      end;
    TPhase.Offsets:
      begin
        Result := NextOffsetRequest(ARequest);
        if not Result then
        begin
          Finish;
        end;
      end;
  end;
end;

function TAtlasAvAnalysis.Next(out ARequest: TAtlasAvRequest): Boolean;
begin
  ARequest := Default(TAtlasAvRequest);
  if FHasPending then
  begin
    ARequest := FPending;
    Exit(True);
  end;
  Result := False;
  while not Result and (FPhase <> TPhase.Done) do
  begin
    Result := PhaseRequest(ARequest);
  end;
  if Result then
  begin
    FPending := ARequest;
    FHasPending := True;
  end;
end;

procedure TAtlasAvAnalysis.Answer(AOk: Boolean; const AText: string);
begin
  if not FHasPending then
  begin
    Exit;
  end;
  FHasPending := False;
  case FPhase of
    TPhase.Links:
      AnswerLink(AOk, AText);
    TPhase.Headers:
      AnswerHeader(AOk, AText);
    TPhase.Offsets:
      AnswerOffset(AOk, AText);
  end;
end;

procedure TAtlasAvAnalysis.Abort;
var
  mIndex: Integer;
begin
  FHasPending := False;
  for mIndex := 0 to High(FChecks) do
  begin
    if FChecks[mIndex].State = TAtlasAvCheckState.Pending then
    begin
      FChecks[mIndex].State := TAtlasAvCheckState.NotEvaluated;
    end;
  end;
  Finish;
end;

procedure TAtlasAvAnalysis.Finish;
var
  mCheck: Integer;
begin
  if FPhase = TPhase.Done then
  begin
    Exit;
  end;
  FPhase := TPhase.Done;
  // Feld und Versatz bleiben aus den Offset-Fragen; alles andere hier.
  FVerdict.Causes := Length(FCauses);
  if Length(FCauses) = 1 then
  begin
    mCheck := FCauses[0];
    FVerdict.HasCulprit := True;
    FVerdict.Culprit := LinkOf(mCheck);
    FVerdict.Value := FData[mCheck].Value;
    case FChecks[mCheck].State of
      TAtlasAvCheckState.NilValue:
        begin
          FVerdict.Kind := TAtlasAvVerdictKind.NilLink;
          FVerdict.VmtAccess := FMessage.AddressKnown and (FMessage.Address = 0) and
            (FVerdict.Culprit.Kind in [TAtlasAvLinkKind.ClassRef, TAtlasAvLinkKind.InterfaceRef]);
          // Kein Feld bestätigt, aber eine Schätzung passt (Offset-Fragen übersprungen).
          if (FVerdict.Field = '') and (FOffsets.Estimate >= 0) and (FOffsets.Candidates <> nil) then
          begin
            FVerdict.Field := FVerdict.Culprit.Fields[FOffsets.Estimate].Name;
            FVerdict.FieldOffset := FVerdict.Culprit.Fields[FOffsets.Estimate].Offset;
          end;
        end;
      TAtlasAvCheckState.Freed:
        FVerdict.Kind := TAtlasAvVerdictKind.Freed;
      TAtlasAvCheckState.Invalid:
        FVerdict.Kind := TAtlasAvVerdictKind.Invalid;
      TAtlasAvCheckState.OutOfRange:
        begin
          FVerdict.Kind := TAtlasAvVerdictKind.OutOfRange;
          FVerdict.Index := Int64(FData[mCheck].Value);
          FVerdict.Length := FData[mCheck].Length;
        end;
    end;
  end
  else if (Length(FCauses) = 0) and FMessage.AddressKnown and
    TAtlasAvValues.NearFreedPattern(FMessage.Address, FPointerSize) then
  begin
    // Kein Glied ist schuld, aber die Adresse liegt im Füllmuster: Zugriff über ein freigegebenes Objekt.
    FVerdict.Kind := TAtlasAvVerdictKind.FreedMemory;
    FVerdict.Value := FMessage.Address;
  end
  else
  begin
    FVerdict.Kind := TAtlasAvVerdictKind.Ambiguous;
  end;
end;

function TAtlasAvAnalysis.Verdict: TAtlasAvVerdict;
begin
  Result := FVerdict;
end;

end.
