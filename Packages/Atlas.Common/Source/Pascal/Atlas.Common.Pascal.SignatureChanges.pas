unit Atlas.Common.Pascal.SignatureChanges;

// Textbausteine für „Signatur ändern“ (#100) ohne Index und Protokoll:
//   - neue Parameterliste für Deklaration (mit den vorhandenen Standardwerten)
//     und Rumpf (ohne) aus der Liste der Änderungen bilden und prüfen,
//   - Argumente eines Aufrufs umstellen, ergänzen oder entfernen,
//   - die alte Signatur als Überladung, die an die neue weiterreicht.
// Köpfe lesen, Parameterliste und Kopf als Text, Verwendungen eines Namens:
// Atlas.Common.Pascal.Signatures. Neue Parameter bekommen nie einen
// Standardwert; vorhandene bleiben, wo sie stehen. Was zur Routine gehört
// (Vorfahren, Nachfahren, Interfaces, Aufrufer), sammelt
// Atlas.Common.Lsp.ChangeSignature.

interface

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Signatures;

type
  /// <summary>Ein Parameter der neuen Signatur.</summary>
  TParameterChange = record
    /// <summary>Stelle in der alten Liste; -1 = neuer Parameter.</summary>
    Origin: Integer;
    Name: string;
    /// <summary>Nur bei neuen Parametern; vorhandene behalten Typ und Modifizierer.</summary>
    TypeName: string;
    Modifier: string;
    /// <summary>Neue Parameter: Wert, den bisherige Aufrufer übergeben.</summary>
    Value: string;
    class function Kept(AOrigin: Integer; const AName: string): TParameterChange; static;
    class function Added(const AName, ATypeName, AModifier, AValue: string): TParameterChange; static;
  end;

  /// <summary>Änderung der Argumente eines Aufrufs: alte Parameter (für Standardwerte ausgelassener Argumente),
  /// die neue Signatur und je neuem Parameter der Wert (Index wie Changes, '' = Value der Änderung).</summary>
  TCallChange = record
    Old: TArray<TSignatureParameter>;
    Changes: TArray<TParameterChange>;
    Values: TArray<string>;
    class function Create(const AOld: TArray<TSignatureParameter>; const AChanges: TArray<TParameterChange>;
      const AValues: TArray<string>): TCallChange; static;
  end;

  TChangeSignature = class
  public
    /// <summary>Fehlertext oder '': Neue Parameter brauchen Namen, Typ und Wert; Namen eindeutig; kein neuer
    /// Parameter hinter einem mit Standardwert; jede alte Stelle höchstens einmal.</summary>
    class function Validate(const AOld: TArray<TSignatureParameter>; const AChanges: TArray<TParameterChange>): string;
      static;
    /// <summary>Parameter der neuen Signatur zu AOld (den Parametern dieses Kopfes). Umbenannt wird nur, wo
    /// der neue Name vom Namen in ARootNames abweicht; sonst bleibt der eigene Name.</summary>
    class function NewParameters(const AOld: TArray<TSignatureParameter>; const AChanges: TArray<TParameterChange>;
      const ARootNames: TArray<string>; AWithDefaults: Boolean): TArray<TSignatureParameter>; static;
    /// <summary>Ersetzt die Klammern samt Inhalt (oder fügt sie hinter dem Namen ein).</summary>
    class function HeaderEdit(const ATokens: TArray<TPascalToken>; const AHeader: TSignatureHeader;
      const AList: string): TTextEdit; static;
    /// <summary>Neue Argumente des Aufrufs an ANameToken nach AChange. False, wenn sich nichts ändert.</summary>
    class function CallEdit(const AText: string; const ATokens: TArray<TPascalToken>; ANameToken: Integer;
      const AChange: TCallChange; out AEdit: TTextEdit): Boolean; static;
    /// <summary>Aufruf der neuen Signatur aus der alten Überladung: alte Parameter nach Namen, neue mit Value.
    /// Mit "Result := " bei Funktionen.</summary>
    class function ForwardCall(const AHeader: TSignatureHeader; const AOld: TArray<TSignatureParameter>;
      const AChanges: TArray<TParameterChange>): string; static;
  end;

implementation

uses
  System.StrUtils,
  System.Generics.Collections,
  System.Generics.Defaults,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Pascal.RoutineSignatures,
  Atlas.Common.Pascal.TokenCursor,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TEditingChangeSignatureText = (TheParameterDoesNotBelong, TheParameterAppearsTwiceIn, TheTypeForTheNew,
    TheValueThatExistingCallers, TheNewParameterWouldCome, IsNotAValidParameter);

const
  cTexts: array[TEditingChangeSignatureText] of TAtlasText = (
    (De: 'Der Parameter "%s" gehört nicht zur alten Signatur.';
     En: 'The parameter "%s" does not belong to the old signature.'),
    (De: 'Der Parameter "%s" steht zweimal in der Liste.'; En: 'The parameter "%s" appears twice in the list.'),
    (De: 'Für den neuen Parameter "%s" fehlt der Typ.'; En: 'The type for the new parameter "%s" is missing.'),
    (De: 'Für den neuen Parameter "%s" fehlt der Wert, den die bisherigen Aufrufer übergeben.';
     En: 'The value that existing callers pass for the new parameter "%s" is missing.'),
    (De: 'Der neue Parameter "%s" stünde hinter einem Parameter mit Standardwert. Bitte weiter vorn einfügen.';
     En: 'The new parameter "%s" would come after a parameter with a default value. Please insert it further to the ' +
      'front.'),
    (De: '"%s" ist kein gültiger Parametername.'; En: '"%s" is not a valid parameter name.'));

{$SCOPEDENUMS OFF}

{ TParameterChange }

class function TParameterChange.Kept(AOrigin: Integer; const AName: string): TParameterChange;
begin
  Result := Default(TParameterChange);
  Result.Origin := AOrigin;
  Result.Name := AName;
end;

class function TParameterChange.Added(const AName, ATypeName, AModifier, AValue: string): TParameterChange;
begin
  Result := Default(TParameterChange);
  Result.Origin := -1;
  Result.Name := AName;
  Result.TypeName := ATypeName;
  Result.Modifier := AModifier;
  Result.Value := AValue;
end;

{ TCallChange }

class function TCallChange.Create(const AOld: TArray<TSignatureParameter>; const AChanges: TArray<TParameterChange>;
  const AValues: TArray<string>): TCallChange;
begin
  Result.Old := AOld;
  Result.Changes := AChanges;
  Result.Values := AValues;
end;

function NamedBefore(const AChanges: TArray<TParameterChange>; AIndex: Integer): Boolean;
var
  mOther: Integer;
begin
  for mOther := 0 to AIndex - 1 do
  begin
    if SameText(AChanges[mOther].Name, AChanges[AIndex].Name) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Fehler eines behaltenen Parameters; '' ohne. Merkt ihn in AUsed und einen Standardwert in
/// ASeenDefault.</summary>
function KeptProblem(const AOld: TArray<TSignatureParameter>; const AChange: TParameterChange;
  var AUsed: TArray<Boolean>; var ASeenDefault: Boolean): string;
begin
  Result := '';
  if AChange.Origin > High(AOld) then
  begin
    Result := cTexts[TEditingChangeSignatureText.TheParameterDoesNotBelong].Fmt([AChange.Name]);
  end
  else if AUsed[AChange.Origin] then
  begin
    Result := cTexts[TEditingChangeSignatureText.TheParameterAppearsTwiceIn].Fmt([AOld[AChange.Origin].Name]);
  end
  else
  begin
    AUsed[AChange.Origin] := True;
    ASeenDefault := ASeenDefault or (AOld[AChange.Origin].DefaultValue <> '');
  end;
end;

/// <summary>Fehler eines neuen Parameters; '' ohne. Atlas erzeugt keine Standardwerte; hinter einem Parameter mit
/// Standardwert (ASeenDefault) ginge es nur mit einem.</summary>
function AddedProblem(const AChange: TParameterChange; ASeenDefault: Boolean): string;
begin
  Result := '';
  if Trim(AChange.TypeName) = '' then
  begin
    Result := cTexts[TEditingChangeSignatureText.TheTypeForTheNew].Fmt([AChange.Name]);
  end
  else if Trim(AChange.Value) = '' then
  begin
    Result := cTexts[TEditingChangeSignatureText.TheValueThatExistingCallers].Fmt([AChange.Name]);
  end
  else if ASeenDefault then
  begin
    Result := cTexts[TEditingChangeSignatureText.TheNewParameterWouldCome].Fmt([AChange.Name]);
  end;
end;

{ TChangeSignature }

class function TChangeSignature.Validate(const AOld: TArray<TSignatureParameter>;
  const AChanges: TArray<TParameterChange>): string;
var
  mIndex: Integer;
  mUsed: TArray<Boolean>;
  mSeenDefault: Boolean;
begin
  Result := '';
  SetLength(mUsed, Length(AOld));
  mSeenDefault := False;
  mIndex := 0;
  while (Result = '') and (mIndex <= High(AChanges)) do
  begin
    if not TPascalLexer.IsIdentifierName(AChanges[mIndex].Name) then
    begin
      Result := cTexts[TEditingChangeSignatureText.IsNotAValidParameter].Fmt([AChanges[mIndex].Name]);
    end
    else if NamedBefore(AChanges, mIndex) then
    begin
      Result := cTexts[TEditingChangeSignatureText.TheParameterAppearsTwiceIn].Fmt([AChanges[mIndex].Name]);
    end
    else if AChanges[mIndex].Origin >= 0 then
    begin
      Result := KeptProblem(AOld, AChanges[mIndex], mUsed, mSeenDefault);
    end
    else
    begin
      Result := AddedProblem(AChanges[mIndex], mSeenDefault);
    end;
    Inc(mIndex);
  end;
end;

class function TChangeSignature.NewParameters(const AOld: TArray<TSignatureParameter>;
  const AChanges: TArray<TParameterChange>; const ARootNames: TArray<string>;
  AWithDefaults: Boolean): TArray<TSignatureParameter>;
var
  mChange: TParameterChange;
  mParameter: TSignatureParameter;
  mRenamed: Boolean;
begin
  Result := nil;
  for mChange in AChanges do
  begin
    if mChange.Origin >= 0 then
    begin
      if mChange.Origin > High(AOld) then
      begin
        Continue;
      end;
      mParameter := AOld[mChange.Origin];
      mRenamed := (mChange.Origin <= High(ARootNames)) and not SameText(mChange.Name, ARootNames[mChange.Origin]);
      if mRenamed or (mChange.Origin > High(ARootNames)) then
      begin
        mParameter.Name := mChange.Name;
      end;
      if not AWithDefaults then
      begin
        mParameter.DefaultValue := '';
      end;
    end
    else
    begin
      mParameter := Default(TSignatureParameter);
      mParameter.Group := -1;
      mParameter.Name := mChange.Name;
      mParameter.TypeName := Trim(mChange.TypeName);
      mParameter.Modifier := LowerCase(Trim(mChange.Modifier));
    end;
    Result := Result + [mParameter];
  end;
end;

class function TChangeSignature.HeaderEdit(const ATokens: TArray<TPascalToken>; const AHeader: TSignatureHeader;
  const AList: string): TTextEdit;
begin
  if AHeader.OpenToken >= 0 then
  begin
    Result := TTextEdit.Create(TTextRange.Create(ATokens[AHeader.OpenToken].StartPos,
      ATokens[AHeader.CloseToken].EndPos), AList);
  end
  else
  begin
    Result := TTextEdit.Create(TTextRange.Create(ATokens[AHeader.NameToken].EndPos,
      ATokens[AHeader.NameToken].EndPos), AList);
  end;
end;

function ReadCallArguments(const AText: string; const ATokens: TArray<TPascalToken>; ANameToken: Integer;
  out AOpen, AClose: Integer; out AArguments: TArray<string>): Boolean;
var
  mValue: string;
begin
  AArguments := nil;
  AClose := -1;
  AOpen := TPascalSignatures.SkipGenerics(ATokens, FollowingCode(ATokens, ANameToken));
  if not TPascalSignatures.SymbolAt(ATokens, AOpen, '(') then
  begin
    AOpen := -1;
    Exit(True);
  end;
  AClose := TPascalSignatures.ClosingBracket(ATokens, AOpen);
  if AClose > FollowingCode(ATokens, AOpen) then
  begin
    for mValue in TRoutineSignatures.SplitTopLevel(
      TPascalSignatures.TokensText(AText, ATokens, FollowingCode(ATokens, AOpen), PreviousCode(ATokens, AClose)), ',') do
    begin
      AArguments := AArguments + [Trim(mValue)];
    end;
  end;
  Result := AClose >= 0;
end;

/// <summary>Neues Argument für AChange.Changes[AIndex]: das alte Argument, bei neuen Parametern der Wert.
/// AOmitted: Das Argument war ausgelassen (Standardwert).</summary>
function NewArgument(const AChange: TCallChange; const AOldArguments: TArray<string>; AIndex: Integer;
  out AOmitted: Boolean): string;
var
  mOrigin: Integer;
begin
  mOrigin := AChange.Changes[AIndex].Origin;
  AOmitted := False;
  Result := '';
  if mOrigin < 0 then
  begin
    if AIndex <= High(AChange.Values) then
    begin
      Result := AChange.Values[AIndex];
    end;
    if Result = '' then
    begin
      Result := AChange.Changes[AIndex].Value;
    end;
  end
  else if mOrigin <= High(AOldArguments) then
  begin
    Result := AOldArguments[mOrigin];
  end
  else
  begin
    AOmitted := True;
    if mOrigin <= High(AChange.Old) then
    begin
      Result := AChange.Old[mOrigin].DefaultValue;
    end;
  end;
end;

/// <summary>Neue Argumente; ausgelassene Standardwerte am Ende bleiben ausgelassen.</summary>
function NewArguments(const AChange: TCallChange; const AOldArguments: TArray<string>): TArray<string>;
var
  mIndex, mLast: Integer;
  mOmitted: TArray<Boolean>;
begin
  SetLength(Result, Length(AChange.Changes));
  SetLength(mOmitted, Length(AChange.Changes));
  for mIndex := 0 to High(AChange.Changes) do
  begin
    Result[mIndex] := NewArgument(AChange, AOldArguments, mIndex, mOmitted[mIndex]);
  end;
  mLast := High(Result);
  while (mLast >= 0) and mOmitted[mLast] do
  begin
    Dec(mLast);
  end;
  SetLength(Result, mLast + 1);
end;

class function TChangeSignature.CallEdit(const AText: string; const ATokens: TArray<TPascalToken>;
  ANameToken: Integer; const AChange: TCallChange; out AEdit: TTextEdit): Boolean;
var
  mOpen, mClose: Integer;
  mOldArguments, mNewArguments: TArray<string>;
  mJoined: string;
begin
  AEdit := Default(TTextEdit);
  if not ReadCallArguments(AText, ATokens, ANameToken, mOpen, mClose, mOldArguments) then
  begin
    Exit(False);
  end;
  mNewArguments := NewArguments(AChange, mOldArguments);
  mJoined := string.Join(', ', mNewArguments);
  Result := not ((Length(mNewArguments) = Length(mOldArguments)) and (mJoined = string.Join(', ', mOldArguments))) and
    ((mOpen >= 0) or (mJoined <> ''));
  if not Result then
  begin
    Exit;
  end;
  if mOpen < 0 then
  begin
    AEdit := TTextEdit.Create(TTextRange.Create(ATokens[ANameToken].EndPos, ATokens[ANameToken].EndPos),
      '(' + mJoined + ')');
  end
  else if mJoined = '' then
  begin
    // Foo() wird zu Foo.
    AEdit := TTextEdit.Create(TTextRange.Create(ATokens[ANameToken].EndPos, ATokens[mClose].EndPos), '');
  end
  else
  begin
    AEdit := TTextEdit.Create(TTextRange.Create(ATokens[mOpen].StartPos, ATokens[mClose].EndPos),
      '(' + mJoined + ')');
  end;
end;

class function TChangeSignature.ForwardCall(const AHeader: TSignatureHeader; const AOld: TArray<TSignatureParameter>;
  const AChanges: TArray<TParameterChange>): string;
var
  mArguments: TArray<string>;
  mChange: TParameterChange;
  mName: string;
begin
  mArguments := nil;
  for mChange in AChanges do
  begin
    if (mChange.Origin >= 0) and (mChange.Origin <= High(AOld)) then
    begin
      mArguments := mArguments + [AOld[mChange.Origin].Name];
    end
    else
    begin
      mArguments := mArguments + [mChange.Value];
    end;
  end;
  mName := AHeader.QualifiedName;
  if LastDelimiter('.', mName) > 0 then
  begin
    mName := Copy(mName, LastDelimiter('.', mName) + 1, MaxInt);
  end;
  Result := mName;
  if Length(mArguments) > 0 then
  begin
    Result := Result + '(' + string.Join(', ', mArguments) + ')';
  end;
  if AHeader.IsFunction then
  begin
    Result := 'Result := ' + Result;
  end;
  Result := Result + ';';
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Pascal.SignatureChanges', cTexts);

end.
