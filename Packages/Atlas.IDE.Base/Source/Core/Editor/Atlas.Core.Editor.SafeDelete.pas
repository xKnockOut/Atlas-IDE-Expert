unit Atlas.Core.Editor.SafeDelete;

// „Sicher löschen“ (#716), Kern im Plugin ohne VCL und ToolsAPI: Argumente
// für die Befehle des Servers (Alt+Entf baut [uri, position] selbst, die
// Code-Aktion liefert sie), die Antwort der Prüfung
// (atlas.server.safeDelete.prepare) und welche Rückfragen nötig sind:
// Überschreibungen und Folgeschritte nach der Einstellung ask, always oder
// never; Verwendungen (samt nicht mitgelöschter Überschreibungen) brauchen
// die Wahl Abbrechen, Anzeigen oder Trotzdem löschen; die Vorschau erscheint
// mit Verwendungen, bei einer ganzen Unit oder mit
// refactoring.safeDeletePreviewWhenUnused, sonst wird sofort gelöscht.

interface

uses
  System.Generics.Collections,
  System.SysUtils,
  System.JSON;

type
  TAtlasSafeDeleteUsage = record
    FileName: string;
    /// <summary>Ab 0.</summary>
    Line: Integer;
    Character: Integer;
    Text: string;
    /// <summary>code, form, interface, uses oder override.</summary>
    Kind: string;
  end;

  TAtlasSafeDeleteInfo = record
    /// <summary>Methode, Feld, …, Unit.</summary>
    Kind: string;
    Name: string;
    Title: string;
    Usages: TArray<TAtlasSafeDeleteUsage>;
    Overrides: TArray<TAtlasSafeDeleteUsage>;
    /// <summary>Was dadurch unbenutzt wird ("FCache", "uses Helpers").</summary>
    Cascade: TArray<string>;
    Warnings: TArray<string>;
    PreviewWhenUnused: Boolean;
    /// <summary>ask, always oder never.</summary>
    CascadeMode: string;
    OverridesMode: string;
    class function FromJson(const AValue: TJSONValue): TAtlasSafeDeleteInfo; static;
    function IsUnit: Boolean;
    /// <summary>Verwendungen, die gegen das Löschen sprechen; Überschreibungen nur, wenn sie bleiben.</summary>
    function Blocking(AIncludeOverrides: Boolean): TArray<TAtlasSafeDeleteUsage>;
    /// <summary>Vorschau statt sofort löschen?</summary>
    function NeedsPreview(AForced: Boolean): Boolean;
  end;

  {$SCOPEDENUMS ON}
  TAtlasSafeDeleteAnswer = (Ask, Always, Never);
  {$SCOPEDENUMS OFF}

  TAtlasSafeDelete = class
  public const
    cClientCommand = 'atlas.safeDelete';
    cPrepareCommand = 'atlas.server.safeDelete.prepare';
    cApplyCommand = 'atlas.server.safeDelete';
    /// <summary>Alt+Entf.</summary>
    cDefaultKey = $802E;
  public
    /// <summary>[uri, position].</summary>
    class function Arguments(const AUri: string; ALine, ACharacter: Integer): string; static;
    /// <summary>AArgumentsJson ([uri, position]) mit den Antworten als drittem Argument.</summary>
    class function ApplyArguments(const AArgumentsJson: string; AOverrides, ACascade, AForce: Boolean): string;
      static;
    /// <summary>ask, always, never; Unbekanntes gilt als ask.</summary>
    class function AnswerOf(const AMode: string): TAtlasSafeDeleteAnswer; static;
    /// <summary>Zeilen für eine Rückfrage: höchstens AMax, dann "… n weitere" über AMore (Format mit %d).</summary>
    class function Listing(const AItems: TArray<string>; AMax: Integer; const AMore: string): string; static;
  end;

implementation

function StringOf(const AObject: TJSONObject; const AName: string): string;
begin
  Result := '';
  if AObject.GetValue(AName) is TJSONString then
  begin
    Result := AObject.GetValue(AName).Value;
  end;
end;

function UsagesOf(const AObject: TJSONObject; const AName: string): TArray<TAtlasSafeDeleteUsage>;
var
  mItem: TJSONValue;
  mUsage: TAtlasSafeDeleteUsage;
begin
  Result := nil;
  if not (AObject.GetValue(AName) is TJSONArray) then
  begin
    Exit;
  end;
  for mItem in TJSONArray(AObject.GetValue(AName)) do
  begin
    if not (mItem is TJSONObject) then
    begin
      Continue;
    end;
    mUsage := Default(TAtlasSafeDeleteUsage);
    mUsage.FileName := StringOf(TJSONObject(mItem), 'file');
    TJSONObject(mItem).TryGetValue<Integer>('line', mUsage.Line);
    TJSONObject(mItem).TryGetValue<Integer>('character', mUsage.Character);
    mUsage.Text := StringOf(TJSONObject(mItem), 'text');
    mUsage.Kind := StringOf(TJSONObject(mItem), 'kind');
    Result := Result + [mUsage];
  end;
end;

function StringsOf(const AObject: TJSONObject; const AName: string): TArray<string>;
var
  mItem: TJSONValue;
begin
  Result := nil;
  if AObject.GetValue(AName) is TJSONArray then
  begin
    for mItem in TJSONArray(AObject.GetValue(AName)) do
    begin
      Result := Result + [mItem.Value];
    end;
  end;
end;

{ TAtlasSafeDeleteInfo }

class function TAtlasSafeDeleteInfo.FromJson(const AValue: TJSONValue): TAtlasSafeDeleteInfo;
var
  mAnswer: TJSONObject;
begin
  Result := Default(TAtlasSafeDeleteInfo);
  Result.CascadeMode := 'ask';
  Result.OverridesMode := 'ask';
  if not (AValue is TJSONObject) then
  begin
    Exit;
  end;
  mAnswer := TJSONObject(AValue);
  Result.Kind := StringOf(mAnswer, 'kind');
  Result.Name := StringOf(mAnswer, 'name');
  Result.Title := StringOf(mAnswer, 'title');
  Result.Usages := UsagesOf(mAnswer, 'usages');
  Result.Overrides := UsagesOf(mAnswer, 'overrides');
  Result.Cascade := StringsOf(mAnswer, 'cascade');
  Result.Warnings := StringsOf(mAnswer, 'warnings');
  Result.PreviewWhenUnused := (mAnswer.GetValue('previewWhenUnused') is TJSONBool) and
    TJSONBool(mAnswer.GetValue('previewWhenUnused')).AsBoolean;
  if StringOf(mAnswer, 'cascadeMode') <> '' then
  begin
    Result.CascadeMode := StringOf(mAnswer, 'cascadeMode');
  end;
  if StringOf(mAnswer, 'overridesMode') <> '' then
  begin
    Result.OverridesMode := StringOf(mAnswer, 'overridesMode');
  end;
end;

function TAtlasSafeDeleteInfo.IsUnit: Boolean;
begin
  Result := SameText(Kind, 'Unit');
end;

function TAtlasSafeDeleteInfo.Blocking(AIncludeOverrides: Boolean): TArray<TAtlasSafeDeleteUsage>;
begin
  Result := Usages;
  if not AIncludeOverrides then
  begin
    Result := Result + Overrides;
  end;
end;

function TAtlasSafeDeleteInfo.NeedsPreview(AForced: Boolean): Boolean;
begin
  Result := AForced or PreviewWhenUnused or IsUnit;
end;

{ TAtlasSafeDelete }

class function TAtlasSafeDelete.Arguments(const AUri: string; ALine, ACharacter: Integer): string;
var
  mList: TJSONArray;
  mPosition: TJSONObject;
begin
  mList := TJSONArray.Create;
  try
    mList.Add(AUri);
    mPosition := TJSONObject.Create;
    mPosition.AddPair('line', TJSONNumber.Create(ALine));
    mPosition.AddPair('character', TJSONNumber.Create(ACharacter));
    mList.AddElement(mPosition);
    Result := mList.ToJSON;
  finally
    mList.Free;
  end;
end;

class function TAtlasSafeDelete.ApplyArguments(const AArgumentsJson: string; AOverrides, ACascade,
  AForce: Boolean): string;
var
  mParsed: TJSONValue;
  mList: TJSONArray;
  mChoices: TJSONObject;
begin
  mParsed := TJSONObject.ParseJSONValue(AArgumentsJson);
  try
    if mParsed is TJSONArray then
    begin
      mList := TJSONArray.Create;
      try
        // Nur uri und Position übernehmen, die Antworten kommen frisch dazu.
        if TJSONArray(mParsed).Count > 0 then
        begin
          mList.AddElement(TJSONArray(mParsed).Items[0].Clone as TJSONValue);
        end;
        if TJSONArray(mParsed).Count > 1 then
        begin
          mList.AddElement(TJSONArray(mParsed).Items[1].Clone as TJSONValue);
        end;
        mChoices := TJSONObject.Create;
        mChoices.AddPair('overrides', TJSONBool.Create(AOverrides));
        mChoices.AddPair('cascade', TJSONBool.Create(ACascade));
        mChoices.AddPair('force', TJSONBool.Create(AForce));
        mList.AddElement(mChoices);
        Result := mList.ToJSON;
      finally
        mList.Free;
      end;
    end
    else
    begin
      Result := AArgumentsJson;
    end;
  finally
    mParsed.Free;
  end;
end;

class function TAtlasSafeDelete.AnswerOf(const AMode: string): TAtlasSafeDeleteAnswer;
begin
  if SameText(AMode, 'always') then
  begin
    Result := TAtlasSafeDeleteAnswer.Always;
  end
  else if SameText(AMode, 'never') then
  begin
    Result := TAtlasSafeDeleteAnswer.Never;
  end
  else
  begin
    Result := TAtlasSafeDeleteAnswer.Ask;
  end;
end;

class function TAtlasSafeDelete.Listing(const AItems: TArray<string>; AMax: Integer; const AMore: string): string;
var
  mIndex: Integer;
begin
  Result := '';
  for mIndex := 0 to High(AItems) do
  begin
    if mIndex >= AMax then
    begin
      Result := Result + sLineBreak + Format(AMore, [Length(AItems) - AMax]);
      Break;
    end;
    if Result <> '' then
    begin
      Result := Result + sLineBreak;
    end;
    Result := Result + AItems[mIndex];
  end;
end;

end.
