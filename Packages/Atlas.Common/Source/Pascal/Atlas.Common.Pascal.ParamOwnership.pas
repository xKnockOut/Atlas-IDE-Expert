unit Atlas.Common.Pascal.ParamOwnership;

// Was eine Routine mit einem übergebenen Objekt macht, je Parameter aus ihrem
// Rumpf (Freigabe über Unit-Grenzen). Der Index-Extraktor hängt die Zusammenfassung
// an die Symbole der Routine (TIndexSymbol.ParamOwnership), die Leckregeln und
// die Marke „Wer gibt das frei?“ fragen sie beim Aufruf ab
// (Atlas.Common.Semantics.CallOwnership). So sieht Atlas auch dann, ob ein Objekt
// freigegeben wird, wenn es an eine Routine einer anderen Unit geht.
//
//   NoObject  Parameter eines einfachen Typs (string, Integer, Interface …) oder ohne Rumpf: keine Aussage nötig
//   Unknown   nicht sicher einzuordnen: out, neu belegt, in einer lokalen Routine oder anonymen Methode benutzt,
//             an einen Aufruf über ein anderes Objekt weitergegeben, asm oder with in der Routine
//   Borrows   nur gelesen bzw. gefüllt (Mitglieder, Vergleich, lesende Routinen); Weitergaben an Routinen, die
//             über ihren Namen auffindbar sind, stehen in Forwards und gelten erst nach deren Prüfung
//   Frees     gibt das Objekt frei (Free, FreeAndNil, Destroy …)
//   Keeps     übernimmt es: Zuweisung an Feld, Variable oder Result, Exit(X), X as I, [X], @X, raise X …
//
// Kodierung je Routine als ein Text, Parameter durch ';' getrennt, je Parameter ein Zeichen aus cEffectMarks,
// bei Borrows danach '>' und die Weitergaben "Routine#Stelle" durch ',' getrennt (Stelle ab 0):
//   "b;-;f"          erster Parameter geliehen, zweiter einfach, dritter freigegeben
//   "b>Fill#1"       geliehen, aber an Fill als zweites Argument weitergegeben
// '' = nichts zu sagen (keine Parameter oder nur einfache bzw. unklare).

interface

uses
  Atlas.Common.Pascal.SyntaxTree;

type
{$SCOPEDENUMS ON}
  TParamEffect = (NoObject, Unknown, Borrows, Frees, Keeps);
{$SCOPEDENUMS OFF}

  /// <summary>Weitergabe eines Parameters an eine Routine, die über ihren Namen auffindbar ist.</summary>
  TParamForward = record
    Callee: string;
    /// <summary>Stelle des Arguments ab 0.</summary>
    Argument: Integer;
  end;

  TParamSummary = record
    Effect: TParamEffect;
    Forwards: TArray<TParamForward>;
  end;

  TParamOwnership = class
  public const
    cEffectMarks: array[TParamEffect] of Char = ('-', '?', 'b', 'f', 'k');
    /// <summary>Höchstens so viele Weitergaben je Parameter; mehr gelten als Unknown.</summary>
    cMaxForwards = 8;
  public
    /// <summary>Zusammenfassung der Routine ARoutine (RoutineDecl mit Rumpf und Parameterliste); '' ohne
    /// Aussage.</summary>
    class function Summarize(ARoutine: TSyntaxNode): string; static;
    /// <summary>Zusammenfassungen je Parameter wie Summarize, unkodiert; nil ohne Rumpf oder Parameterliste.
    /// </summary>
    class function Analyze(ARoutine: TSyntaxNode): TArray<TParamSummary>; static;
    class function Encode(const ASummaries: TArray<TParamSummary>): string; static;
    /// <summary>Zusammenfassung des Parameters AParam (ab 0) aus AEncoded; False, wenn es ihn dort nicht gibt.
    /// </summary>
    class function Decode(const AEncoded: string; AParam: Integer; out ASummary: TParamSummary): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Text.Names,
  Atlas.Common.Pascal.ObjectUses,
  Atlas.Common.Pascal.RoutineBody,
  Atlas.Common.Pascal.SyntaxNodes;

const
  /// <summary>Typen, die kein Objekt sind; Vergleich ohne Groß-/Kleinschreibung.</summary>
  cSimpleTypes: array[0..37] of string = ('string', 'Integer', 'Cardinal', 'Int64', 'UInt64', 'Boolean', 'Byte',
    'Word', 'LongInt', 'LongWord', 'NativeInt', 'NativeUInt', 'ShortInt', 'SmallInt', 'Double', 'Single',
    'Extended', 'Currency', 'Real', 'Char', 'WideChar', 'AnsiChar', 'AnsiString', 'WideString', 'UnicodeString',
    'RawByteString', 'UTF8String', 'ShortString', 'TDateTime', 'TDate', 'TTime', 'Variant', 'OleVariant', 'PChar',
    'Pointer', 'TGUID', 'TBytes', 'TArray');
  cForwardMark = '>';
  cArgumentMark = '#';

/// <summary>Kein Objekt: einfacher Typ, Interface, Array.</summary>
function IsNoObjectType(AParam: TSyntaxNode): Boolean;
var
  mIndex: Integer;
  mType: string;
begin
  for mIndex := 0 to AParam.ChildCount - 1 do
  begin
    case AParam[mIndex].Kind of
      TSyntaxKind.ArrayType:
        Exit(True);
      TSyntaxKind.TypeReference:
        begin
          mType := TTextNames.WithoutGenerics(AParam[mIndex].Name);
          Exit(MatchText(mType, cSimpleTypes) or TTextNames.LooksLikeInterface(mType));
        end;
    else
      // Standardwert und anderes zählen nicht.
    end;
  end;
  // Untypisierter Parameter (const X).
  Result := False;
end;

/// <summary>Name des Aufrufs, über den eine Weitergabe auffindbar ist: Foo(X) und Self.Foo(X); '' sonst.</summary>
function ForwardName(ACall: TSyntaxNode): string;
var
  mCallee: TSyntaxNode;
begin
  Result := '';
  mCallee := ACall[0];
  if mCallee.Kind = TSyntaxKind.Identifier then
  begin
    Result := mCallee.Name;
  end
  else if (mCallee.Kind = TSyntaxKind.MemberAccess) and (mCallee.ChildCount = 1) and
    (mCallee[0].Kind = TSyntaxKind.Identifier) and SameText(mCallee[0].Name, 'Self') then
  begin
    Result := mCallee.Name;
  end;
end;

type
  /// <summary>Sammelt die Vorkommen eines Parameters zu einer Zusammenfassung.</summary>
  TParamScan = record
    Routine: TSyntaxNode;
    Unclear: Boolean;
    Kept: Boolean;
    Freed: Boolean;
    Forwards: TArray<TParamForward>;
    procedure Add(AOccurrence: TSyntaxNode);
    procedure AddForward(const AUse: TObjectUse);
    function Summary: TParamSummary;
  end;

procedure TParamScan.AddForward(const AUse: TObjectUse);
var
  mForward: TParamForward;
begin
  mForward.Callee := ForwardName(AUse.Node);
  mForward.Argument := AUse.Argument;
  if (mForward.Callee = '') or (Length(Forwards) >= TParamOwnership.cMaxForwards) then
  begin
    Unclear := True;
    Exit;
  end;
  SetLength(Forwards, Length(Forwards) + 1);
  Forwards[High(Forwards)] := mForward;
end;

procedure TParamScan.Add(AOccurrence: TSyntaxNode);
var
  mUse: TObjectUse;
begin
  if TSyntaxNodes.Enclosing(AOccurrence, [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod], Routine) <> nil
    then
  begin
    Unclear := True;
    Exit;
  end;
  mUse := TObjectUses.Classify(AOccurrence);
  case mUse.Kind of
    TObjectUseKind.Assigned:
      Unclear := True;
    TObjectUseKind.Release:
      Freed := True;
    TObjectUseKind.Escape:
      Kept := True;
    TObjectUseKind.Argument:
      // Lesende Routinen (Assign, AddStrings, …) leihen nur; ohne Index bleibt der Name das einzige Zeichen.
      if not mUse.Reading then
      begin
        AddForward(mUse);
      end;
  else
    // Use: nur gelesen.
  end;
end;

function TParamScan.Summary: TParamSummary;
begin
  Result := Default(TParamSummary);
  // Neu belegt: Was danach freigegeben wird, ist nicht mehr das übergebene Objekt.
  if Unclear and not Kept and not Freed then
  begin
    Result.Effect := TParamEffect.Unknown;
  end
  else if Kept then
  begin
    Result.Effect := TParamEffect.Keeps;
  end
  else if Freed then
  begin
    Result.Effect := TParamEffect.Frees;
  end
  else
  begin
    Result.Effect := TParamEffect.Borrows;
    Result.Forwards := Forwards;
  end;
end;

/// <summary>Enthält ANode asm oder with? Dort sind Vorkommen nicht sicher einzuordnen.</summary>
function HasAsmOrWith(ANode: TSyntaxNode): Boolean;
begin
  Result := TSyntaxNodes.ContainsKind(ANode, TSyntaxKind.AsmBlock) or
    TSyntaxNodes.ContainsKind(ANode, TSyntaxKind.WithStatement);
end;

function SummaryOf(ARoutine, ABody, AParam: TSyntaxNode; const AName: string): TParamSummary;
var
  mScan: TParamScan;
  mOccurrence: TSyntaxNode;
begin
  Result := Default(TParamSummary);
  if IsNoObjectType(AParam) then
  begin
    Result.Effect := TParamEffect.NoObject;
    Exit;
  end;
  if AParam.Modifier = TParameterModifier.OutParam then
  begin
    Result.Effect := TParamEffect.Unknown;
    Exit;
  end;
  mScan := Default(TParamScan);
  mScan.Routine := ARoutine;
  for mOccurrence in TSyntaxNode.IdentifierUses(ABody, AName) do
  begin
    mScan.Add(mOccurrence);
  end;
  Result := mScan.Summary;
end;

{ TParamOwnership }

class function TParamOwnership.Analyze(ARoutine: TSyntaxNode): TArray<TParamSummary>;
var
  mHeader, mParams, mParam, mBody: TSyntaxNode;
  mIndex: Integer;
  mName: string;
  mUnclear: Boolean;
  mSummary: TParamSummary;
  mSummaries: TList<TParamSummary>;
begin
  Result := nil;
  mHeader := ARoutine.FindChild(TSyntaxKind.RoutineHeader);
  mBody := TRoutineBody.BodyOf(ARoutine);
  if (mHeader = nil) or (mBody = nil) then
  begin
    Exit;
  end;
  mParams := mHeader.FindChild(TSyntaxKind.Parameters);
  if mParams = nil then
  begin
    Exit;
  end;
  mUnclear := HasAsmOrWith(ARoutine);
  mSummaries := TList<TParamSummary>.Create;
  try
    for mIndex := 0 to mParams.ChildCount - 1 do
    begin
      mParam := mParams[mIndex];
      if mParam.Kind <> TSyntaxKind.Parameter then
      begin
        Continue;
      end;
      for mName in mParam.Name.Split([',']) do
      begin
        if mUnclear and not IsNoObjectType(mParam) then
        begin
          mSummary := Default(TParamSummary);
          mSummary.Effect := TParamEffect.Unknown;
        end
        else
        begin
          mSummary := SummaryOf(ARoutine, mBody, mParam, Trim(mName));
        end;
        mSummaries.Add(mSummary);
      end;
    end;
    Result := mSummaries.ToArray;
  finally
    mSummaries.Free;
  end;
end;

class function TParamOwnership.Encode(const ASummaries: TArray<TParamSummary>): string;
var
  mBuilder: TStringBuilder;
  mIndex, mForward: Integer;
  mUseful: Boolean;
begin
  mUseful := False;
  for mIndex := 0 to High(ASummaries) do
  begin
    mUseful := mUseful or (ASummaries[mIndex].Effect in [TParamEffect.Borrows, TParamEffect.Frees,
      TParamEffect.Keeps]);
  end;
  if not mUseful then
  begin
    Exit('');
  end;
  mBuilder := TStringBuilder.Create;
  try
    for mIndex := 0 to High(ASummaries) do
    begin
      if mIndex > 0 then
      begin
        mBuilder.Append(';');
      end;
      mBuilder.Append(cEffectMarks[ASummaries[mIndex].Effect]);
      for mForward := 0 to High(ASummaries[mIndex].Forwards) do
      begin
        if mForward = 0 then
        begin
          mBuilder.Append(cForwardMark);
        end
        else
        begin
          mBuilder.Append(',');
        end;
        mBuilder.Append(ASummaries[mIndex].Forwards[mForward].Callee).Append(cArgumentMark)
          .Append(ASummaries[mIndex].Forwards[mForward].Argument);
      end;
    end;
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

class function TParamOwnership.Summarize(ARoutine: TSyntaxNode): string;
begin
  Result := Encode(Analyze(ARoutine));
end;

/// <summary>Weitergaben "Foo#1,Bar#0" in ASummary.</summary>
procedure DecodeForwards(const AText: string; var ASummary: TParamSummary);
var
  mEntry: string;
  mMark: Integer;
  mForward: TParamForward;
begin
  for mEntry in AText.Split([',']) do
  begin
    mMark := mEntry.LastIndexOf(cArgumentMark);
    if (mMark <= 0) or not TryStrToInt(mEntry.Substring(mMark + 1), mForward.Argument) then
    begin
      ASummary.Effect := TParamEffect.Unknown;
      ASummary.Forwards := nil;
      Exit;
    end;
    mForward.Callee := mEntry.Substring(0, mMark);
    SetLength(ASummary.Forwards, Length(ASummary.Forwards) + 1);
    ASummary.Forwards[High(ASummary.Forwards)] := mForward;
  end;
end;

class function TParamOwnership.Decode(const AEncoded: string; AParam: Integer;
  out ASummary: TParamSummary): Boolean;
var
  mParts: TArray<string>;
  mPart: string;
  mEffect: TParamEffect;
begin
  ASummary := Default(TParamSummary);
  mParts := AEncoded.Split([';']);
  Result := (AEncoded <> '') and (AParam >= 0) and (AParam < Length(mParts)) and (mParts[AParam] <> '');
  if not Result then
  begin
    Exit;
  end;
  mPart := mParts[AParam];
  ASummary.Effect := TParamEffect.Unknown;
  for mEffect := Low(TParamEffect) to High(TParamEffect) do
  begin
    if mPart[1] = cEffectMarks[mEffect] then
    begin
      ASummary.Effect := mEffect;
    end;
  end;
  if (ASummary.Effect = TParamEffect.Borrows) and (Length(mPart) > 1) and (mPart[2] = cForwardMark) then
  begin
    DecodeForwards(Copy(mPart, 3, MaxInt), ASummary);
  end;
end;

end.
