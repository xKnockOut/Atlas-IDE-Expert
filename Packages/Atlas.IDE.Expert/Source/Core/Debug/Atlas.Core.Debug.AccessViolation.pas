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
    NearNil = $10000;
    MaxOffsetChecks = 32;
  private type
    {$SCOPEDENUMS ON}
    TPhase = (Links, Headers, Offsets, Done);
    {$SCOPEDENUMS OFF}
  private
    FChains: TAtlasAvChains;
    FMessage: TAtlasAvMessage;
    FPointerSize: Integer;
    FAllowCalls: Boolean;
    FChecks: TArray<TAtlasAvCheck>;
    FValues: TArray<UInt64>;
    FKnown: TArray<Boolean>;
    FPhase: TPhase;
    FCheck: Integer;
    /// <summary>Kopf: 0 = erstes Wort gefragt, 1 = zweites.</summary>
    FHeaderWord: Integer;
    FPending: TAtlasAvRequest;
    FHasPending: Boolean;
    FLengths: TArray<Int64>;
    FCauses: TArray<Integer>;
    FVerdict: TAtlasAvVerdict;
    FOffsetCandidates: TArray<Integer>;
    FOffsetNext: Integer;
    FEstimate: Integer;
    procedure SkipRestOfChain(ACheck: Integer; AState: TAtlasAvCheckState);
    function NextLinkRequest(out ARequest: TAtlasAvRequest): Boolean;
    function NextHeaderRequest(out ARequest: TAtlasAvRequest): Boolean;
    function NextOffsetRequest(out ARequest: TAtlasAvRequest): Boolean;
    procedure AnswerLink(AOk: Boolean; const AText: string);
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
  FreedPatterns32: array[0..2] of UInt64 = ($80808080, $FEEEFEEE, $DDDDDDDD);
  FreedPatterns64: array[0..2] of UInt64 = ($8080808080808080, $FEEEFEEEFEEEFEEE, $DDDDDDDDDDDDDDDD);

function LowerTrim(const AText: string): string;
begin
  Result := LowerCase(Trim(AText));
end;

/// <summary>Hexzahl ab APos (Leerzeichen davor erlaubt); False ohne Ziffer.</summary>
function ReadHex(const AText: string; APos: Integer; out AValue: UInt64): Boolean;
var
  Digits: Integer;
  Ch: Char;
begin
  AValue := 0;
  Digits := 0;
  while (APos <= Length(AText)) and (AText[APos] = ' ') do
    Inc(APos);
  if (APos <= Length(AText)) and (AText[APos] = '$') then
    Inc(APos);
  while (APos <= Length(AText)) and (Digits < 16) do
  begin
    Ch := AText[APos];
    if CharInSet(Ch, ['0'..'9']) then
      AValue := AValue * 16 + UInt64(Ord(Ch) - Ord('0'))
    else if CharInSet(Ch, ['a'..'f']) then
      AValue := AValue * 16 + UInt64(Ord(Ch) - Ord('a') + 10)
    else if CharInSet(Ch, ['A'..'F']) then
      AValue := AValue * 16 + UInt64(Ord(Ch) - Ord('A') + 10)
    else
      Break;
    Inc(Digits);
    Inc(APos);
  end;
  Result := Digits > 0;
end;

{ TAtlasAvMessage }

class function TAtlasAvMessage.Parse(const AClassName, AMessage: string): TAtlasAvMessage;
const
  // Wörter vor der Zieladresse, deutsch und englisch; die Adresse des Codes steht davor ("bei Adresse").
  Operations: array[0..5] of string = ('lesen von adresse', 'schreiben von adresse', 'ausführung von adresse',
    'read of address', 'write of address', 'execution of address');
  Kinds: array[0..5] of TAtlasAvOperation = (TAtlasAvOperation.Read, TAtlasAvOperation.Write,
    TAtlasAvOperation.Execute, TAtlasAvOperation.Read, TAtlasAvOperation.Write, TAtlasAvOperation.Execute);
var
  Text, ClassName_: string;
  Index, At: Integer;
  Value: UInt64;
begin
  Result := Default(TAtlasAvMessage);
  Text := LowerCase(AMessage);
  ClassName_ := LowerTrim(AClassName);
  Result.IsAccessViolation := (ClassName_ = 'eaccessviolation') or (Pos('zugriffsverletzung', Text) > 0) or
    (Pos('access violation', Text) > 0);
  // EExternalException trägt nur mit passender Meldung eine Zugriffsverletzung (C0000005).
  if (ClassName_ = 'eexternalexception') and not Result.IsAccessViolation then
    Result.IsAccessViolation := Pos('c0000005', Text) > 0;
  if not Result.IsAccessViolation then
    Exit;
  for Index := Low(Operations) to High(Operations) do
  begin
    At := Pos(Operations[Index], Text);
    if (At > 0) and ReadHex(AMessage, At + Length(Operations[Index]), Value) then
    begin
      Result.AddressKnown := True;
      Result.Address := Value;
      Result.Operation := Kinds[Index];
      Exit;
    end;
  end;
end;

{ TAtlasAvAnalysis }

constructor TAtlasAvAnalysis.Create(const AChains: TAtlasAvChains; const AMessage: TAtlasAvMessage;
  APointerSize: Integer; AAllowCalls: Boolean);
var
  ChainIndex, LinkIndex: Integer;
  Check: TAtlasAvCheck;
begin
  inherited Create;
  FChains := AChains;
  FMessage := AMessage;
  FPointerSize := APointerSize;
  FAllowCalls := AAllowCalls;
  for ChainIndex := 0 to High(FChains.Chains) do
    for LinkIndex := 0 to High(FChains.Chains[ChainIndex].Links) do
    begin
      Check := Default(TAtlasAvCheck);
      Check.Chain := ChainIndex;
      Check.Link := LinkIndex;
      Check.Expression := FChains.Chains[ChainIndex].Links[LinkIndex].Expression;
      FChecks := FChecks + [Check];
    end;
  SetLength(FValues, Length(FChecks));
  SetLength(FKnown, Length(FChecks));
  SetLength(FLengths, Length(FChecks));
  FPhase := TPhase.Links;
  FCheck := 0;
end;

class function TAtlasAvAnalysis.HexText(AValue: UInt64): string;
begin
  if AValue <= $FFFFFFFF then
    Result := '$' + IntToHex(AValue, 8)
  else
    Result := '$' + IntToHex(AValue, 16);
end;

class function TAtlasAvAnalysis.ParseAddress(const AText: string; out AValue: UInt64): Boolean;
var
  Text: string;
  Signed: Int64;
begin
  AValue := 0;
  Text := Trim(AText);
  // Typumwandlungen zeigt der Debugger mitunter eingeklammert.
  if (Length(Text) > 2) and (Text[1] = '(') and (Text[Length(Text)] = ')') then
    Text := Trim(Copy(Text, 2, Length(Text) - 2));
  if SameText(Text, 'nil') then
    Exit(True);
  if Text = '' then
    Exit(False);
  if Text[1] = '$' then
    Exit(ReadHex(Text, 1, AValue) and (Length(Text) <= 17));
  if StartsText('0x', Text) then
    Exit(ReadHex(Text, 3, AValue) and (Length(Text) <= 18));
  Result := TryStrToInt64(Text, Signed);
  if Result then
    AValue := UInt64(Signed)
  else
    // Dezimal über Int64 hinaus (Füllmuster unter Win64 als Zahl).
    Result := TryStrToUInt64(Text, AValue);
end;

class function TAtlasAvAnalysis.ParseInteger(const AText: string; out AValue: Int64): Boolean;
var
  Address: UInt64;
begin
  Result := TryStrToInt64(Trim(AText), AValue);
  if not Result and ParseAddress(AText, Address) then
  begin
    AValue := Int64(Address);
    Result := True;
  end;
end;

class function TAtlasAvAnalysis.IsFreedPattern(AValue: UInt64; APointerSize: Integer): Boolean;
var
  Pattern: UInt64;
begin
  if APointerSize = 8 then
  begin
    for Pattern in FreedPatterns64 do
      if AValue = Pattern then
        Exit(True);
  end;
  // Auch unter Win64 stehen in 32-Bit-Feldern die kurzen Muster.
  for Pattern in FreedPatterns32 do
    if AValue = Pattern then
      Exit(True);
  Result := False;
end;

class function TAtlasAvAnalysis.NearFreedPattern(AValue: UInt64; APointerSize: Integer): Boolean;
var
  Pattern: UInt64;
begin
  for Pattern in FreedPatterns32 do
    if (AValue >= Pattern) and (AValue - Pattern < NearNil) then
      Exit(True);
  if APointerSize = 8 then
    for Pattern in FreedPatterns64 do
      if (AValue >= Pattern) and (AValue - Pattern < NearNil) then
        Exit(True);
  Result := False;
end;

function TAtlasAvAnalysis.LinkOf(ACheck: Integer): TAtlasAvLink;
begin
  Result := FChains.Chains[FChecks[ACheck].Chain].Links[FChecks[ACheck].Link];
end;

procedure TAtlasAvAnalysis.SkipRestOfChain(ACheck: Integer; AState: TAtlasAvCheckState);
var
  Index: Integer;
begin
  Index := ACheck + 1;
  while (Index <= High(FChecks)) and (FChecks[Index].Chain = FChecks[ACheck].Chain) do
  begin
    if FChecks[Index].State = TAtlasAvCheckState.Pending then
      FChecks[Index].State := AState;
    Inc(Index);
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
  Link: TAtlasAvLink;
begin
  Result := False;
  while FCheck <= High(FChecks) do
  begin
    if FChecks[FCheck].State <> TAtlasAvCheckState.Pending then
    begin
      Inc(FCheck);
      Continue;
    end;
    Link := LinkOf(FCheck);
    if Link.Call and not FAllowCalls then
    begin
      // Getter oder Funktion: ohne allowCalls nichts ausführen, auch nichts dahinter.
      FChecks[FCheck].State := TAtlasAvCheckState.NotEvaluated;
      SkipRestOfChain(FCheck, TAtlasAvCheckState.NotEvaluated);
      Inc(FCheck);
      Continue;
    end;
    ARequest := Default(TAtlasAvRequest);
    ARequest.Expression := 'Pointer(' + Link.Expression + ')';
    ARequest.Purpose := TAtlasAvPurpose.Value;
    ARequest.SideEffects := Link.Call;
    Exit(True);
  end;
end;

procedure TAtlasAvAnalysis.AnswerLink(AOk: Boolean; const AText: string);
var
  Link: TAtlasAvLink;
  Value: UInt64;
  Number: Int64;
begin
  Link := LinkOf(FCheck);
  case FPending.Purpose of
    TAtlasAvPurpose.Value, TAtlasAvPurpose.PlainValue:
      begin
        if AOk and ParseAddress(AText, Value) then
        begin
          FValues[FCheck] := Value;
          FKnown[FCheck] := True;
          if Value = 0 then
            FChecks[FCheck].State := TAtlasAvCheckState.NilValue
          else if IsFreedPattern(Value, FPointerSize) then
            FChecks[FCheck].State := TAtlasAvCheckState.Freed
          else if Value < NearNil then
            FChecks[FCheck].State := TAtlasAvCheckState.Invalid
          else
            FChecks[FCheck].State := TAtlasAvCheckState.Ok;
          FChecks[FCheck].Value := HexText(Value);
        end
        else if FPending.Purpose = TAtlasAvPurpose.Value then
        begin
          // Die Umwandlung kennt nicht jeder Debugger: den Ausdruck selbst fragen.
          FPending.Expression := Link.Expression;
          FPending.Purpose := TAtlasAvPurpose.PlainValue;
          FHasPending := True;
          Exit;
        end
        else if AOk then
        begin
          FChecks[FCheck].State := TAtlasAvCheckState.Ok;
          FChecks[FCheck].Value := AText;
        end
        else
          FChecks[FCheck].State := TAtlasAvCheckState.Failed;
        if FChecks[FCheck].State in [TAtlasAvCheckState.NilValue, TAtlasAvCheckState.Freed,
          TAtlasAvCheckState.Invalid] then
        begin
          AddCause(FCheck);
          SkipRestOfChain(FCheck, TAtlasAvCheckState.NotReached);
        end
        else if (FChecks[FCheck].State = TAtlasAvCheckState.Ok) and (Link.Kind = TAtlasAvLinkKind.DynArray) and
          (Link.IndexText <> '') and Link.IndexPlain then
        begin
          FPending.Expression := 'Length(' + Link.Expression + ')';
          FPending.Purpose := TAtlasAvPurpose.Length;
          FPending.SideEffects := False;
          FHasPending := True;
          Exit;
        end;
      end;
    TAtlasAvPurpose.Length:
      if AOk and ParseInteger(AText, Number) then
      begin
        FLengths[FCheck] := Number;
        FPending.Expression := Link.IndexText;
        FPending.Purpose := TAtlasAvPurpose.Index;
        FHasPending := True;
        Exit;
      end;
    TAtlasAvPurpose.Index:
      if AOk and ParseInteger(AText, Number) then
      begin
        FChecks[FCheck].Value := Format('%s · %s = %d / %d', [FChecks[FCheck].Value, Link.IndexText, Number,
          FLengths[FCheck]]);
        if (Number < 0) or (Number >= FLengths[FCheck]) then
        begin
          FChecks[FCheck].State := TAtlasAvCheckState.OutOfRange;
          FValues[FCheck] := UInt64(Number);
          AddCause(FCheck);
          SkipRestOfChain(FCheck, TAtlasAvCheckState.NotReached);
        end;
      end;
  end;
  Inc(FCheck);
end;

function TAtlasAvAnalysis.NextHeaderRequest(out ARequest: TAtlasAvRequest): Boolean;
var
  Link: TAtlasAvLink;
begin
  Result := False;
  while FCheck <= High(FChecks) do
  begin
    Link := LinkOf(FCheck);
    if (FChecks[FCheck].State = TAtlasAvCheckState.Ok) and FKnown[FCheck] and
      (Link.Kind = TAtlasAvLinkKind.ClassRef) then
    begin
      ARequest := Default(TAtlasAvRequest);
      // Erstes Wort der Instanz (VMT-Zeiger) bzw. das zweite; nach der Freigabe das Füllmuster.
      ARequest.Expression := 'PNativeUInt(' + HexText(FValues[FCheck] + UInt64(FHeaderWord * FPointerSize)) + ')^';
      ARequest.Purpose := TAtlasAvPurpose.Header;
      Exit(True);
    end;
    Inc(FCheck);
  end;
end;

procedure TAtlasAvAnalysis.AnswerHeader(AOk: Boolean; const AText: string);
var
  Value: UInt64;
begin
  if AOk and ParseAddress(AText, Value) and IsFreedPattern(Value, FPointerSize) then
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
  Link: TAtlasAvLink;
  Index: Integer;
begin
  FOffsetCandidates := nil;
  FOffsetNext := 0;
  FEstimate := -1;
  if (Length(FCauses) <> 1) or (FChecks[FCauses[0]].State <> TAtlasAvCheckState.NilValue) or
    not FMessage.AddressKnown or (FMessage.Address >= NearNil) then
    Exit;
  Link := LinkOf(FCauses[0]);
  if not (Link.Kind in [TAtlasAvLinkKind.ClassRef, TAtlasAvLinkKind.InterfaceRef]) then
    Exit;
  if (FMessage.Address = 0) or (Link.Kind = TAtlasAvLinkKind.InterfaceRef) then
    Exit;
  // Geschätzter Treffer zuerst prüfen, dann alle Felder der Reihe nach.
  for Index := 0 to High(Link.Fields) do
    if Link.Fields[Index].Offset = Integer(FMessage.Address) then
      FEstimate := Index;
  if FEstimate >= 0 then
    FOffsetCandidates := FOffsetCandidates + [FEstimate];
  for Index := 0 to Min(High(Link.Fields), MaxOffsetChecks - 1) do
    if Index <> FEstimate then
      FOffsetCandidates := FOffsetCandidates + [Index];
end;

function TAtlasAvAnalysis.NextOffsetRequest(out ARequest: TAtlasAvRequest): Boolean;
var
  Link: TAtlasAvLink;
begin
  Result := False;
  if FOffsetNext > High(FOffsetCandidates) then
  begin
    // Alle Felder nachgefragt, keines liegt an der Adresse: Die Schätzung ist widerlegt.
    if FOffsetCandidates <> nil then
      FEstimate := -1;
    FOffsetCandidates := nil;
    Exit;
  end;
  Link := LinkOf(FCauses[0]);
  ARequest := Default(TAtlasAvRequest);
  ARequest.Expression := 'NativeInt(@' + Link.TypeName + '(nil).' + Link.Fields[FOffsetCandidates[FOffsetNext]].Name +
    ')';
  ARequest.Purpose := TAtlasAvPurpose.Offset;
  Result := True;
end;

procedure TAtlasAvAnalysis.AnswerOffset(AOk: Boolean; const AText: string);
var
  Number: Int64;
  Link: TAtlasAvLink;
begin
  Link := LinkOf(FCauses[0]);
  if not (AOk and ParseInteger(AText, Number)) then
  begin
    // Der Debugger kann den Versatz nicht ausrechnen: bei der Schätzung bleiben.
    if FEstimate >= 0 then
    begin
      FVerdict.Field := Link.Fields[FEstimate].Name;
      FVerdict.FieldOffset := Link.Fields[FEstimate].Offset;
      FVerdict.FieldExact := False;
    end;
    FOffsetCandidates := nil;
    Exit;
  end;
  if UInt64(Number) = FMessage.Address then
  begin
    FVerdict.Field := Link.Fields[FOffsetCandidates[FOffsetNext]].Name;
    FVerdict.FieldOffset := Integer(Number);
    FVerdict.FieldExact := True;
    FOffsetCandidates := nil;
    Exit;
  end;
  Inc(FOffsetNext);
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
  while FPhase <> TPhase.Done do
    case FPhase of
      TPhase.Links:
        if NextLinkRequest(ARequest) then
          Break
        else
        begin
          FPhase := TPhase.Headers;
          FCheck := 0;
          // Ohne nil: freigegebene Objekte am Kopf erkennen.
          if FCauses <> nil then
            FPhase := TPhase.Offsets;
          if FPhase = TPhase.Offsets then
            StartOffsets;
        end;
      TPhase.Headers:
        if (FCauses = nil) and NextHeaderRequest(ARequest) then
          Break
        else
        begin
          FPhase := TPhase.Offsets;
          StartOffsets;
        end;
      TPhase.Offsets:
        if NextOffsetRequest(ARequest) then
          Break
        else
          Finish;
    end;
  if FPhase = TPhase.Done then
    Exit(False);
  FPending := ARequest;
  FHasPending := True;
  Result := True;
end;

procedure TAtlasAvAnalysis.Answer(AOk: Boolean; const AText: string);
begin
  if not FHasPending then
    Exit;
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
  Index: Integer;
begin
  FHasPending := False;
  for Index := 0 to High(FChecks) do
    if FChecks[Index].State = TAtlasAvCheckState.Pending then
      FChecks[Index].State := TAtlasAvCheckState.NotEvaluated;
  Finish;
end;

procedure TAtlasAvAnalysis.Finish;
var
  Check: Integer;
begin
  if FPhase = TPhase.Done then
    Exit;
  FPhase := TPhase.Done;
  // Feld und Versatz bleiben aus den Offset-Fragen; alles andere hier.
  FVerdict.Causes := Length(FCauses);
  if Length(FCauses) = 1 then
  begin
    Check := FCauses[0];
    FVerdict.HasCulprit := True;
    FVerdict.Culprit := LinkOf(Check);
    FVerdict.Value := FValues[Check];
    case FChecks[Check].State of
      TAtlasAvCheckState.NilValue:
        begin
          FVerdict.Kind := TAtlasAvVerdictKind.NilLink;
          FVerdict.VmtAccess := FMessage.AddressKnown and (FMessage.Address = 0) and
            (FVerdict.Culprit.Kind in [TAtlasAvLinkKind.ClassRef, TAtlasAvLinkKind.InterfaceRef]);
          // Kein Feld bestätigt, aber eine Schätzung passt (Offset-Fragen übersprungen).
          if (FVerdict.Field = '') and (FEstimate >= 0) and (FOffsetCandidates <> nil) then
          begin
            FVerdict.Field := FVerdict.Culprit.Fields[FEstimate].Name;
            FVerdict.FieldOffset := FVerdict.Culprit.Fields[FEstimate].Offset;
          end;
        end;
      TAtlasAvCheckState.Freed:
        FVerdict.Kind := TAtlasAvVerdictKind.Freed;
      TAtlasAvCheckState.Invalid:
        FVerdict.Kind := TAtlasAvVerdictKind.Invalid;
      TAtlasAvCheckState.OutOfRange:
        begin
          FVerdict.Kind := TAtlasAvVerdictKind.OutOfRange;
          FVerdict.Index := Int64(FValues[Check]);
          FVerdict.Length := FLengths[Check];
        end;
    end;
  end
  else if (Length(FCauses) = 0) and FMessage.AddressKnown and NearFreedPattern(FMessage.Address, FPointerSize) then
  begin
    // Kein Glied ist schuld, aber die Adresse liegt im Füllmuster: Zugriff über ein freigegebenes Objekt.
    FVerdict.Kind := TAtlasAvVerdictKind.FreedMemory;
    FVerdict.Value := FMessage.Address;
  end
  else
    FVerdict.Kind := TAtlasAvVerdictKind.Ambiguous;
end;

function TAtlasAvAnalysis.Verdict: TAtlasAvVerdict;
begin
  Result := FVerdict;
end;

end.
