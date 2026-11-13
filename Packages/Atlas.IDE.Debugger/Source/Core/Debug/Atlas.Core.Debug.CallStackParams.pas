unit Atlas.Core.Debug.CallStackParams;

// Parameter eines Rahmens im Fenster „Aufrufstapel“ (#843), ohne VCL und Open Tools API:
//   - SplitArguments: Werte aus dem Rahmentext der IDE („Unit1.TForm1.Import(5,'a, b',$2A3F2C0)“ → 5, 'a, b',
//     $2A3F2C0). Kommas in Strings, Klammern und eckigen Klammern trennen nicht; „Name=Wert“ (LLDB) liefert den
//     Namen mit.
//   - Namen und Typen kommen vom Server (atlas.server.routineParameters, ReadAnswer); Combine ordnet sie den Werten
//     zu, wenn die Anzahl passt (bei Methoden darf vorn Self stehen). Sonst bleiben die Werte ohne Namen.
//   - Auswertung: Was Atlas für einen Parameter auswertet (ExpressionFor) und wie das Ergebnis aussieht
//     (ObjectText, ValueText). Strings stehen in Anführungszeichen, Objekte mit Klasse und Namensfeld.

interface

uses
  System.JSON;

type
  TAtlasCallStackParam = record
    /// <summary>Name aus der Deklaration bzw. aus „Name=Wert“; '' = unbekannt.</summary>
    Name: string;
    /// <summary>Typ laut Deklaration; '' = unbekannt.</summary>
    TypeName: string;
    /// <summary>Wert aus dem Rahmentext der IDE.</summary>
    Raw: string;
    /// <summary>Lesbarer Wert nach der Auswertung; '' = Raw zeigen.</summary>
    Value: string;
    /// <summary>Ausgewertet (auch erfolglos): nicht noch einmal fragen.</summary>
    Done: Boolean;
    /// <summary>Anders als beim letzten Halt an derselben Stelle.</summary>
    Changed: Boolean;
    /// <summary>Angezeigter Wert: Value, sonst Raw.</summary>
    function Shown: string;
    /// <summary>„Name = Wert“ bzw. nur der Wert ohne Namen.</summary>
    function Text: string;
  end;

  TAtlasCallStackParamList = TArray<TAtlasCallStackParam>;

  /// <summary>Deklarierter Parameter laut Server.</summary>
  TAtlasCallStackDeclared = record
    Name: string;
    TypeName: string;
  end;

  TAtlasCallStackDeclaredList = TArray<TAtlasCallStackDeclared>;

  TAtlasCallStackParams = record
  public const
    cCommand = 'atlas.server.routineParameters';
    /// <summary>Längere Werte kürzt die Anzeige.</summary>
    cMaxValue = 80;
  public
    /// <summary>Werte zwischen den äußeren Klammern der Kopfzeile; nil ohne Klammern.</summary>
    class function SplitArguments(const AHeader: string): TArray<string>; static;
    /// <summary>Parameter aus der Kopfzeile, Namen aus „Name=Wert“, falls die IDE sie nennt.</summary>
    class function FromHeader(const AHeader: string): TAtlasCallStackParamList; static;
    /// <summary>Argumente des Serverbefehls als JSON: [uri, line] (Zeile ab 0).</summary>
    class function Arguments(const AUri: string; ALine: Integer): string; static;
    /// <summary>Antwort des Servers; False ohne format 1.</summary>
    class function ReadAnswer(const AText: string; out ARoutine: string;
      out ADeclared: TAtlasCallStackDeclaredList): Boolean; static;
    /// <summary>Namen und Typen zuordnen: gleiche Anzahl, oder bei einer Methode (AMethod) ein Wert mehr vorn
    /// (Self). Sonst bleibt AParams unverändert; Result: zugeordnet.</summary>
    class function Combine(var AParams: TAtlasCallStackParamList; const ADeclared: TAtlasCallStackDeclaredList;
      AMethod: Boolean): Boolean; static;
    /// <summary>Sieht ARaw wie eine Adresse aus ($2A3F2C0, 0x…)?</summary>
    class function IsAddress(const ARaw: string): Boolean; static;
    /// <summary>Was Atlas für AParam auswertet; '' = nichts. Im obersten Rahmen (ATop) der Name, sonst bei einer
    /// Adresse mit bekanntem Typ eine Typumwandlung der Adresse (unabhängig vom gewählten Rahmen).</summary>
    class function ExpressionFor(const AParam: TAtlasCallStackParam; ATop: Boolean): string; static;
    /// <summary>Wert lesbar machen: String in Anführungszeichen (AStringType), lange Werte gekürzt.</summary>
    class function ValueText(const AValue: string; AStringType: Boolean): string; static;
    /// <summary>Objekt: Klasse und Namensfeld („TKunde 'Meier'“); ohne Namen nur die Klasse mit Adresse.</summary>
    class function ObjectText(const AClassName, ANameValue, AAddress: string): string; static;
    /// <summary>Ist ATypeName ein String-Typ (string, AnsiString, …)?</summary>
    class function IsStringType(const ATypeName: string): Boolean; static;
    /// <summary>Sieht das Ergebnis einer Auswertung wie ein Objekt bzw. Record aus („(FName: …)“)?</summary>
    class function IsStructure(const AValue: string): Boolean; static;
    /// <summary>Werte als „Name = Wert, …“.</summary>
    class function ListText(const AParams: TAtlasCallStackParamList): string; static;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Text.Json;

{ TAtlasCallStackParam }

function TAtlasCallStackParam.Shown: string;
begin
  Result := Value;
  if Result = '' then
  begin
    Result := Raw;
  end;
end;

function TAtlasCallStackParam.Text: string;
begin
  Result := Shown;
  if Name <> '' then
  begin
    Result := Name + ' = ' + Result;
  end;
end;

{ TAtlasCallStackParams }

/// <summary>Index der schließenden Klammer zu AText[AOpen]; 0 ohne.</summary>
function ClosingParen(const AText: string; AOpen: Integer): Integer;
var
  mIndex, mDepth: Integer;
  mQuoted: Boolean;
begin
  Result := 0;
  mDepth := 0;
  mQuoted := False;
  for mIndex := AOpen to Length(AText) do
  begin
    if AText[mIndex] = '''' then
    begin
      mQuoted := not mQuoted;
    end
    else if not mQuoted then
    begin
      case AText[mIndex] of
        '(', '[', '{':
          Inc(mDepth);
        ')', ']', '}':
          begin
            Dec(mDepth);
            if mDepth = 0 then
            begin
              Exit(mIndex);
            end;
          end;
      end;
    end;
  end;
end;

class function TAtlasCallStackParams.SplitArguments(const AHeader: string): TArray<string>;
var
  mOpen, mClose, mIndex, mStart, mDepth: Integer;
  mQuoted: Boolean;
  mInner: string;
begin
  Result := nil;
  mOpen := Pos('(', AHeader);
  if mOpen = 0 then
  begin
    Exit;
  end;
  mClose := ClosingParen(AHeader, mOpen);
  if mClose = 0 then
  begin
    mClose := Length(AHeader) + 1;
  end;
  mInner := Copy(AHeader, mOpen + 1, mClose - mOpen - 1);
  if Trim(mInner) = '' then
  begin
    Exit;
  end;
  mDepth := 0;
  mQuoted := False;
  mStart := 1;
  for mIndex := 1 to Length(mInner) do
  begin
    if mInner[mIndex] = '''' then
    begin
      mQuoted := not mQuoted;
    end
    else if not mQuoted then
    begin
      case mInner[mIndex] of
        '(', '[', '{':
          Inc(mDepth);
        ')', ']', '}':
          Dec(mDepth);
        ',':
          if mDepth = 0 then
          begin
            Result := Result + [Trim(Copy(mInner, mStart, mIndex - mStart))];
            mStart := mIndex + 1;
          end;
      end;
    end;
  end;
  Result := Result + [Trim(Copy(mInner, mStart, MaxInt))];
end;

/// <summary>Bezeichner vor „=“ am Anfang von AText; '' ohne.</summary>
function LeadingName(const AText: string; out AValue: string): string;
var
  mIndex: Integer;
begin
  Result := '';
  AValue := AText;
  mIndex := 1;
  while (mIndex <= Length(AText)) and CharInSet(AText[mIndex], ['A'..'Z', 'a'..'z', '_', '0'..'9']) do
  begin
    Inc(mIndex);
  end;
  if (mIndex > 1) and (mIndex <= Length(AText)) and (AText[mIndex] = '=') and
    not CharInSet(AText[1], ['0'..'9']) then
  begin
    Result := Copy(AText, 1, mIndex - 1);
    AValue := Trim(Copy(AText, mIndex + 1, MaxInt));
  end;
end;

class function TAtlasCallStackParams.FromHeader(const AHeader: string): TAtlasCallStackParamList;
var
  mRaw, mValue: string;
  mParam: TAtlasCallStackParam;
begin
  Result := nil;
  for mRaw in SplitArguments(AHeader) do
  begin
    mParam := Default(TAtlasCallStackParam);
    mParam.Name := LeadingName(mRaw, mValue);
    mParam.Raw := mValue;
    Result := Result + [mParam];
  end;
end;

class function TAtlasCallStackParams.Arguments(const AUri: string; ALine: Integer): string;
var
  mItems: TJSONArray;
begin
  mItems := TJSONArray.Create;
  try
    mItems.Add(AUri);
    mItems.Add(ALine);
    Result := mItems.ToJSON;
  finally
    mItems.Free;
  end;
end;

class function TAtlasCallStackParams.ReadAnswer(const AText: string; out ARoutine: string;
  out ADeclared: TAtlasCallStackDeclaredList): Boolean;
var
  mJson: TJSONObject;
  mList: TJSONArray;
  mIndex: Integer;
  mItem: TAtlasCallStackDeclared;
begin
  ARoutine := '';
  ADeclared := nil;
  Result := False;
  mJson := TJsonRead.ParseObject(AText);
  if mJson = nil then
  begin
    Exit;
  end;
  try
    if TJsonRead.IntOr(mJson, 'format', 0) <> 1 then
    begin
      Exit;
    end;
    ARoutine := TJsonRead.Text(mJson, 'routine');
    mList := TJsonRead.Items(mJson, 'parameters');
    if mList <> nil then
    begin
      for mIndex := 0 to mList.Count - 1 do
      begin
        mItem := Default(TAtlasCallStackDeclared);
        mItem.Name := TJsonRead.Text(TJsonRead.AsObject(mList.Items[mIndex]), 'name');
        mItem.TypeName := TJsonRead.Text(TJsonRead.AsObject(mList.Items[mIndex]), 'type');
        ADeclared := ADeclared + [mItem];
      end;
    end;
    Result := True;
  finally
    mJson.Free;
  end;
end;

class function TAtlasCallStackParams.Combine(var AParams: TAtlasCallStackParamList;
  const ADeclared: TAtlasCallStackDeclaredList; AMethod: Boolean): Boolean;
var
  mOffset, mIndex: Integer;
begin
  mOffset := Length(AParams) - Length(ADeclared);
  Result := (Length(ADeclared) > 0) and ((mOffset = 0) or (AMethod and (mOffset = 1)));
  if not Result then
  begin
    Exit;
  end;
  if mOffset = 1 then
  begin
    AParams[0].Name := 'Self';
  end;
  for mIndex := 0 to High(ADeclared) do
  begin
    AParams[mIndex + mOffset].Name := ADeclared[mIndex].Name;
    AParams[mIndex + mOffset].TypeName := ADeclared[mIndex].TypeName;
  end;
end;

class function TAtlasCallStackParams.IsAddress(const ARaw: string): Boolean;
var
  mDigits: string;
  mChar: Char;
begin
  if ARaw.StartsWith('$') then
  begin
    mDigits := Copy(ARaw, Length('$') + 1, MaxInt);
  end
  else if ARaw.StartsWith('0x', True) then
  begin
    mDigits := Copy(ARaw, Length('0x') + 1, MaxInt);
  end
  else
  begin
    Exit(False);
  end;
  Result := mDigits <> '';
  for mChar in mDigits do
  begin
    if not CharInSet(mChar, ['0'..'9', 'A'..'F', 'a'..'f']) then
    begin
      Exit(False);
    end;
  end;
end;

class function TAtlasCallStackParams.ExpressionFor(const AParam: TAtlasCallStackParam; ATop: Boolean): string;
begin
  Result := '';
  if (AParam.Name = '') or AParam.Done then
  begin
    Exit;
  end;
  if ATop then
  begin
    Result := AParam.Name;
  end
  else if IsAddress(AParam.Raw) and (AParam.TypeName <> '') and not AParam.TypeName.Contains(' ') then
  begin
    Result := AParam.TypeName + '(' + AParam.Raw + ')';
  end;
end;

class function TAtlasCallStackParams.IsStringType(const ATypeName: string): Boolean;
const
  cStrings: array[0..5] of string = ('string', 'AnsiString', 'UnicodeString', 'WideString', 'RawByteString',
    'UTF8String');
var
  mName: string;
begin
  for mName in cStrings do
  begin
    if SameText(mName, ATypeName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TAtlasCallStackParams.IsStructure(const AValue: string): Boolean;
begin
  Result := AValue.StartsWith('(') and AValue.EndsWith(')') and AValue.Contains(':');
end;

class function TAtlasCallStackParams.ValueText(const AValue: string; AStringType: Boolean): string;
begin
  Result := Trim(AValue);
  if AStringType and not Result.StartsWith('''') then
  begin
    Result := '''' + Result.Replace('''', '''''') + '''';
  end;
  if Length(Result) > cMaxValue then
  begin
    Result := Copy(Result, 1, cMaxValue - 1) + '…';
  end;
end;

class function TAtlasCallStackParams.ObjectText(const AClassName, ANameValue, AAddress: string): string;
begin
  Result := AClassName;
  if ANameValue <> '' then
  begin
    Result := Result + ' ' + ValueText(ANameValue, True);
  end
  else if AAddress <> '' then
  begin
    Result := Result + ' (' + AAddress + ')';
  end;
end;

class function TAtlasCallStackParams.ListText(const AParams: TAtlasCallStackParamList): string;
var
  mTexts: TArray<string>;
  mParam: TAtlasCallStackParam;
begin
  mTexts := nil;
  for mParam in AParams do
  begin
    mTexts := mTexts + [mParam.Text];
  end;
  Result := string.Join(', ', mTexts);
end;

end.
