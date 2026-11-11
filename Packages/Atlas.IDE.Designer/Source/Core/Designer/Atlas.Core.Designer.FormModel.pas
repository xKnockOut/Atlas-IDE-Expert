unit Atlas.Core.Designer.FormModel;

// Formulartext im Designer als Liste der Komponenten (#738), ohne VCL und
// Windows. Der Text kommt von TAtlasFormText (wie beim Speichern der .dfm),
// darum stehen darin nur gespeicherte Werte, also keine Vorgaben: genau die
// Eigenschaften, die „gleicher Eigenschaftswert“, die Textliste und die
// Vereinheitlichung brauchen.
// - Einzeilige Werte mit Pfad („Font.Name = 'Tahoma'“), mit + fortgesetzte
//   Strings als ein Wert ('a' + 'b').
// - Ereignisse: Eigenschaft On… mit einem Bezeichner als Wert.
// - Listen ( … ), Kollektionen < … > und Binärdaten { … } überspringt
//   TAtlasFormModel, sie bilden keinen einzelnen Wert.

interface

type
  /// <summary>Gespeicherte Eigenschaft: Pfad wie in der Datei und Wert als DFM-Text.</summary>
  TAtlasFormValue = record
    Path: string;
    Value: string;
    class function Create(const APath, AValue: string): TAtlasFormValue; static;
    /// <summary>„Font.Name = 'Tahoma'“.</summary>
    function Text: string;
  end;

  TAtlasFormObject = record
    Name: string;
    TypeName: string;
    /// <summary>Name des umschließenden Objekts im Text; '' beim Formular selbst.</summary>
    OwnerName: string;
    /// <summary>Tiefe im Text: 0 = Formular, 1 = direkt darin.</summary>
    Depth: Integer;
    Values: TArray<TAtlasFormValue>;
    /// <summary>Path = Ereignis (OnClick), Value = Handler.</summary>
    Events: TArray<TAtlasFormValue>;
    /// <summary>Wert zu APath ohne Groß-/Kleinschreibung; False ohne ihn.</summary>
    function ValueOf(const APath: string; out AValue: string): Boolean;
  end;

  TAtlasFormModel = class
  public
    /// <summary>Objekte des Formulartexts in Textreihenfolge, das Formular zuerst.</summary>
    class function Parse(const AText: string): TArray<TAtlasFormObject>; static;
    /// <summary>Index des Objekts AName ohne Groß-/Kleinschreibung; -1 ohne es.</summary>
    class function IndexOf(const AObjects: TArray<TAtlasFormObject>; const AName: string): Integer; static;
    /// <summary>String-Wert der DFM ('a', 'a'#13'b', mit + verkettet) als Text; False bei anderem.</summary>
    class function StringValue(const AValue: string; out AText: string): Boolean; static;
  end;

implementation

uses
  System.SysUtils;

{ TAtlasFormValue }

class function TAtlasFormValue.Create(const APath, AValue: string): TAtlasFormValue;
begin
  Result.Path := APath;
  Result.Value := AValue;
end;

function TAtlasFormValue.Text: string;
begin
  Result := Path + ' = ' + Value;
end;

{ TAtlasFormObject }

function TAtlasFormObject.ValueOf(const APath: string; out AValue: string): Boolean;
var
  mValue: TAtlasFormValue;
begin
  AValue := '';
  for mValue in Values do
  begin
    if SameText(mValue.Path, APath) then
    begin
      AValue := mValue.Value;
      Exit(True);
    end;
  end;
  Result := False;
end;

function IsIdentifier(const AText: string): Boolean;
var
  mIndex: Integer;
begin
  Result := AText <> '';
  for mIndex := 1 to Length(AText) do
  begin
    if not (CharInSet(AText[mIndex], ['A'..'Z', 'a'..'z', '_']) or
      ((mIndex > 1) and CharInSet(AText[mIndex], ['0'..'9']))) then
    begin
      Exit(False);
    end;
  end;
end;

function IsPath(const AText: string): Boolean;
var
  mPart: string;
begin
  Result := AText <> '';
  for mPart in AText.Split(['.']) do
  begin
    if not IsIdentifier(mPart) then
    begin
      Exit(False);
    end;
  end;
end;

function IsEvent(const APath, AValue: string): Boolean;
begin
  Result := (Length(APath) > 2) and APath.StartsWith('On') and CharInSet(APath[3], ['A'..'Z']) and
    IsIdentifier(APath) and IsIdentifier(AValue);
end;

/// <summary>„object Name: TTyp“ (auch inherited, inline, mit [n] dahinter); False sonst.</summary>
function ObjectLine(const ALine: string; out AName, ATypeName: string): Boolean;
var
  mRest: string;
  mColon, mBracket: Integer;
begin
  AName := '';
  ATypeName := '';
  if ALine.StartsWith('object ') then
  begin
    mRest := Copy(ALine, 8, MaxInt);
  end
  else if ALine.StartsWith('inherited ') then
  begin
    mRest := Copy(ALine, 11, MaxInt);
  end
  else if ALine.StartsWith('inline ') then
  begin
    mRest := Copy(ALine, 8, MaxInt);
  end
  else
  begin
    Exit(False);
  end;
  mBracket := Pos('[', mRest);
  if mBracket > 0 then
  begin
    mRest := Copy(mRest, 1, mBracket - 1);
  end;
  mColon := Pos(':', mRest);
  if mColon > 0 then
  begin
    AName := Trim(Copy(mRest, 1, mColon - 1));
    ATypeName := Trim(Copy(mRest, mColon + 1, MaxInt));
  end
  else
  begin
    ATypeName := Trim(mRest);
  end;
  Result := IsIdentifier(ATypeName) and ((AName = '') or IsIdentifier(AName));
end;

type
  /// <summary>Was Parse gerade überspringt bzw. sammelt.</summary>
  TSkip = (None, List, Binary, Collection, Continued);

  /// <summary>Zustand von Parse.</summary>
  TFormReader = record
    Objects: TArray<TAtlasFormObject>;
    Stack: TArray<Integer>;
    Skip: TSkip;
    /// <summary>Verschachtelte Kollektionen.</summary>
    CollectionDepth: Integer;
    /// <summary>Fortgesetzter String: Pfad und bisheriger Wert.</summary>
    PendingPath: string;
    PendingValue: string;
    procedure Line(const ALine: string);
    procedure Store(const APath, AValue: string);
    procedure Value(const APath, AValue: string);
    procedure Push(const AName, ATypeName: string);
    procedure Pop;
    /// <summary>Zeile je nach Zustand: überspringen, sammeln oder lesen.</summary>
    procedure SkipLine(const ALine: string);
    procedure CollectionLine(const ALine: string);
    procedure ContinuedLine(const ALine: string);
    procedure Content(const ALine: string);
  end;

procedure TFormReader.Store(const APath, AValue: string);
var
  mTop: Integer;
begin
  if Length(Stack) = 0 then
  begin
    Exit;
  end;
  mTop := Stack[High(Stack)];
  if IsEvent(APath, AValue) then
  begin
    Objects[mTop].Events := Objects[mTop].Events + [TAtlasFormValue.Create(APath, AValue)];
  end
  else
  begin
    Objects[mTop].Values := Objects[mTop].Values + [TAtlasFormValue.Create(APath, AValue)];
  end;
end;

procedure TFormReader.Push(const AName, ATypeName: string);
var
  mObject: TAtlasFormObject;
begin
  mObject := Default(TAtlasFormObject);
  mObject.Name := AName;
  mObject.TypeName := ATypeName;
  mObject.Depth := Length(Stack);
  if Length(Stack) > 0 then
  begin
    mObject.OwnerName := Objects[Stack[High(Stack)]].Name;
  end;
  Objects := Objects + [mObject];
  Stack := Stack + [High(Objects)];
end;

procedure TFormReader.Pop;
begin
  if Length(Stack) > 0 then
  begin
    SetLength(Stack, Length(Stack) - 1);
  end;
end;

procedure TFormReader.SkipLine(const ALine: string);
begin
  case Skip of
    TSkip.List:
      if ALine.EndsWith(')') then
      begin
        Skip := TSkip.None;
      end;
    TSkip.Binary:
      if ALine.EndsWith('}') then
      begin
        Skip := TSkip.None;
      end;
    TSkip.Collection:
      CollectionLine(ALine);
    TSkip.Continued:
      ContinuedLine(ALine);
    TSkip.None:
      Content(ALine);
  end;
end;

procedure TFormReader.CollectionLine(const ALine: string);
begin
  // In Einträgen beginnen weitere Kollektionen („Items = <“) und enden mit „end>“.
  if ALine.EndsWith('= <') then
  begin
    Inc(CollectionDepth);
  end
  else if ALine.EndsWith('end>') or (ALine = '>') then
  begin
    Dec(CollectionDepth);
    if CollectionDepth <= 0 then
    begin
      Skip := TSkip.None;
    end;
  end;
end;

procedure TFormReader.ContinuedLine(const ALine: string);
begin
  if PendingValue = '' then
  begin
    PendingValue := ALine;
  end
  else
  begin
    PendingValue := PendingValue + ' ' + ALine;
  end;
  if not ALine.EndsWith('+') then
  begin
    Skip := TSkip.None;
    Store(PendingPath, PendingValue);
  end;
end;

procedure TFormReader.Value(const APath, AValue: string);
begin
  if AValue = '' then
  begin
    // „Hint =“ und der Wert in den folgenden Zeilen.
    Skip := TSkip.Continued;
    PendingPath := APath;
    PendingValue := '';
  end
  else if (AValue[1] = '(') and not AValue.EndsWith(')') then
  begin
    Skip := TSkip.List;
  end
  else if (AValue[1] = '{') and not AValue.EndsWith('}') then
  begin
    Skip := TSkip.Binary;
  end
  else if (AValue[1] = '<') and (AValue <> '<>') then
  begin
    Skip := TSkip.Collection;
    CollectionDepth := 1;
  end
  else if AValue.EndsWith('+') then
  begin
    Skip := TSkip.Continued;
    PendingPath := APath;
    PendingValue := AValue;
  end
  else if not CharInSet(AValue[1], ['(', '{', '<']) then
  begin
    Store(APath, AValue);
  end;
end;

procedure TFormReader.Line(const ALine: string);
var
  mLine: string;
begin
  mLine := Trim(ALine);
  if mLine <> '' then
  begin
    SkipLine(mLine);
  end;
end;

/// <summary>Zeile außerhalb übersprungener Werte: Objekt, Ende oder Eigenschaft.</summary>
procedure TFormReader.Content(const ALine: string);
var
  mName, mTypeName, mPath: string;
  mSeparator: Integer;
begin
  if ObjectLine(ALine, mName, mTypeName) then
  begin
    Push(mName, mTypeName);
    Exit;
  end;
  if ALine = 'end' then
  begin
    Pop;
    Exit;
  end;
  mSeparator := Pos(' =', ALine);
  if mSeparator <= 0 then
  begin
    Exit;
  end;
  mPath := Trim(Copy(ALine, 1, mSeparator - 1));
  if IsPath(mPath) then
  begin
    Value(mPath, Trim(Copy(ALine, mSeparator + 2, MaxInt)));
  end;
end;

{ TAtlasFormModel }

class function TAtlasFormModel.Parse(const AText: string): TArray<TAtlasFormObject>;
var
  mReader: TFormReader;
  mLine: string;
begin
  mReader := Default(TFormReader);
  for mLine in AText.Replace(#13#10, #10).Replace(#13, #10).Split([#10]) do
  begin
    mReader.Line(mLine);
  end;
  Result := mReader.Objects;
end;

class function TAtlasFormModel.IndexOf(const AObjects: TArray<TAtlasFormObject>; const AName: string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(AObjects) do
  begin
    if SameText(AObjects[mIndex].Name, AName) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

/// <summary>Teil ab APos: 'Text' (mit '' für ein Hochkomma) oder #Zahl; False bei anderem.</summary>
function StringPart(const AValue: string; var APos: Integer; var AText: string): Boolean;
var
  mStart, mCode: Integer;
begin
  Result := True;
  if AValue[APos] = '''' then
  begin
    Inc(APos);
    while APos <= Length(AValue) do
    begin
      if AValue[APos] = '''' then
      begin
        if (APos < Length(AValue)) and (AValue[APos + 1] = '''') then
        begin
          AText := AText + '''';
          Inc(APos, 2);
          Continue;
        end;
        Inc(APos);
        Exit;
      end;
      AText := AText + AValue[APos];
      Inc(APos);
    end;
    Exit(False);
  end;
  if AValue[APos] <> '#' then
  begin
    Exit(False);
  end;
  Inc(APos);
  mStart := APos;
  while (APos <= Length(AValue)) and CharInSet(AValue[APos], ['0'..'9']) do
  begin
    Inc(APos);
  end;
  Result := TryStrToInt(Copy(AValue, mStart, APos - mStart), mCode) and (mCode >= 0) and (mCode <= $FFFF);
  if Result then
  begin
    AText := AText + Char(mCode);
  end;
end;

class function TAtlasFormModel.StringValue(const AValue: string; out AText: string): Boolean;
var
  mPos: Integer;
begin
  AText := '';
  mPos := 1;
  Result := False;
  while mPos <= Length(AValue) do
  begin
    if CharInSet(AValue[mPos], [' ', '+']) then
    begin
      Inc(mPos);
      Continue;
    end;
    if not StringPart(AValue, mPos, AText) then
    begin
      Exit(False);
    end;
    Result := True;
  end;
end;

end.
