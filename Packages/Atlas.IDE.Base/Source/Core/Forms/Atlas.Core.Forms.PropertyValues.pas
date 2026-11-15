unit Atlas.Core.Forms.PropertyValues;

// Eigenschaften eines offenen Formulars über RTTI setzen (#309, #721, #1967): Atlas.IDE.Forms.Designer übergibt
// die Wurzelkomponente aus dem Designer und die Änderungen aus TAtlasFormChanges; hier fällt, ob und wie jeder
// DFM-Wert in seine Eigenschaft geht.
// - Pfad wie in der Datei, auch über Objekt-Eigenschaften (Font.Name); jedes Glied bis auf das letzte muss eine
//   gesetzte Objekt-Eigenschaft sein, das letzte eine schreibbare Eigenschaft.
// - Werte nach Art: Strings nur als DFM-String, Ganzzahlen auch als Bezeichner (clRed, crHandPoint), Int64,
//   Aufzählungen nach Namen, Mengen ([a, b]), Gleitkomma invariant. Andere Arten setzt Atlas im Designer nicht.
// - Entfernte Zeile (Rückgängig): Ordinalwerte auf den default der Deklaration, Strings leer; ohne default
//   abgelehnt.
// - Check prüft alle Änderungen, bevor eine gilt; Apply setzt danach. Rückgabe '' oder der Grund in der Sprache
//   der Oberfläche.

interface

uses
  System.Classes,
  System.TypInfo,
  Atlas.Core.Forms.Changes;

type
  TAtlasFormPropertyValues = class
  public
    /// <summary>Komponente AName unter ARoot; '' ist die Wurzel selbst; nil ohne.</summary>
    class function ComponentOf(ARoot: TComponent; const AName: string): TComponent; static;
    /// <summary>Grund „Komponente AName nicht gefunden“.</summary>
    class function ComponentMissing(const AName: string): string; static;
    /// <summary>Löst APath (auch Font.Name) an AComponent auf; '' oder der Grund.</summary>
    class function Resolve(AComponent: TObject; const APath: string; out AInstance: TObject;
      out AProp: PPropInfo): string; static;
    /// <summary>DFM-Wert aus AChange in die Eigenschaft; mit ACheckOnly nur prüfen. '' oder der Grund.</summary>
    class function WriteValue(AInstance: TObject; AProp: PPropInfo; const AChange: TAtlasFormPropertyChange;
      ACheckOnly: Boolean): string; static;
    /// <summary>Ziele aller Änderungen unter ARoot, Werte geprüft; '' oder der Grund (mit Komponentenname).
    /// </summary>
    class function Check(ARoot: TComponent; const AProperties: TArray<TAtlasFormPropertyChange>;
      out ATargets: TArray<TObject>; out AProps: TArray<PPropInfo>): string; static;
    /// <summary>Nach Check: alle Änderungen setzen.</summary>
    class procedure Apply(const ATargets: TArray<TObject>; const AProps: TArray<PPropInfo>;
      const AProperties: TArray<TAtlasFormPropertyChange>); static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Localization.Language;

{$SCOPEDENUMS ON}

type
  /// <summary>Benutzertexte dieser Unit (#1458).</summary>
  TPropertyText = (IsNotAnObjectProperty, IsNotSet, CannotBeSet, HasNoDefaultValue, NotAStringValue, IsNotANumber,
    TypeIsNotSetIn, ComponentNotFound, UnknownValue, UnknownSetElement, NoProperty);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TAtlasLanguage, TPropertyText] of string = (
    ('%s ist keine Objekt-Eigenschaft',
     '%s ist nicht gesetzt',
     '%s lässt sich nicht setzen',
     '%s hat keinen Vorgabewert',
     '%s: kein String-Wert',
     '%s: %s ist keine Zahl',
     '%s: Typ wird im Designer nicht gesetzt',
     'Komponente %s nicht gefunden',
     '%s: unbekannter Wert %s',
     '%s: unbekanntes Element in %s',
     'ohne Eigenschaft'),
    ('%s is not an object property',
     '%s is not set',
     '%s cannot be set',
     '%s has no default value',
     '%s: not a string value',
     '%s: %s is not a number',
     '%s: type is not set in the designer',
     'component %s not found',
     '%s: unknown value %s',
     '%s: unknown element in %s',
     'no property'));

  /// <summary>PropInfo.Default ohne default-Angabe (wie in System.Classes).</summary>
  cNoDefaultValue = Integer($80000000);

/// <summary>Text AId in der Sprache der Oberfläche.</summary>
function UiText(AId: TPropertyText): string;
begin
  Result := cTexts[TAtlasTextLanguage.Current, AId];
end;

/// <summary>Typ der Eigenschaft (Delphi führt ihn über einen Zeiger mehr als FPC).</summary>
function PropTypeOf(AProp: PPropInfo): PTypeInfo;
begin
  {$IFDEF FPC}
  Result := AProp^.PropType;
  {$ELSE}
  Result := AProp^.PropType^;
  {$ENDIF}
end;

/// <summary>Zeile entfernt (Rückgängig, #721): zurück zum Vorgabewert der Deklaration.</summary>
function ResetValue(AInstance: TObject; AProp: PPropInfo; const APath: string; ACheckOnly: Boolean): string;
var
  mKind: TTypeKind;
begin
  Result := '';
  mKind := PropTypeOf(AProp)^.Kind;
  if (mKind in [tkInteger, tkChar, tkWChar, tkEnumeration, tkSet]) and (AProp^.Default <> cNoDefaultValue) then
  begin
    if not ACheckOnly then
    begin
      SetOrdProp(AInstance, AProp, AProp^.Default);
    end;
  end
  else if mKind in [tkString, tkLString, tkWString, tkUString] then
  begin
    if not ACheckOnly then
    begin
      SetStrProp(AInstance, AProp, '');
    end;
  end
  else
  begin
    Result := Format(UiText(TPropertyText.HasNoDefaultValue), [APath]);
  end;
end;

function AssignString(AInstance: TObject; AProp: PPropInfo; const AChange: TAtlasFormPropertyChange;
  ACheckOnly: Boolean): string;
var
  mText: string;
begin
  Result := '';
  if not TAtlasFormChanges.StringValue(AChange.Value, mText) then
  begin
    Result := Format(UiText(TPropertyText.NotAStringValue), [AChange.PropertyPath]);
  end
  else if not ACheckOnly then
  begin
    SetStrProp(AInstance, AProp, mText);
  end;
end;

/// <summary>Ganzzahl oder Bezeichner wie clRed oder crHandPoint.</summary>
function AssignInteger(AInstance: TObject; AProp: PPropInfo; const AChange: TAtlasFormPropertyChange;
  ACheckOnly: Boolean): string;
var
  mNumber: Integer;
  mIdentToInt: TIdentToInt;
begin
  Result := '';
  if not TryStrToInt(AChange.Value, mNumber) then
  begin
    mIdentToInt := FindIdentToInt(PropTypeOf(AProp));
    if not Assigned(mIdentToInt) or not mIdentToInt(AChange.Value, mNumber) then
    begin
      Exit(Format(UiText(TPropertyText.IsNotANumber), [AChange.PropertyPath, AChange.Value]));
    end;
  end;
  if not ACheckOnly then
  begin
    SetOrdProp(AInstance, AProp, mNumber);
  end;
end;

function AssignInt64(AInstance: TObject; AProp: PPropInfo; const AChange: TAtlasFormPropertyChange;
  ACheckOnly: Boolean): string;
var
  mNumber: Int64;
begin
  Result := '';
  if not TryStrToInt64(AChange.Value, mNumber) then
  begin
    Result := Format(UiText(TPropertyText.IsNotANumber), [AChange.PropertyPath, AChange.Value]);
  end
  else if not ACheckOnly then
  begin
    SetInt64Prop(AInstance, AProp, mNumber);
  end;
end;

function AssignEnumeration(AInstance: TObject; AProp: PPropInfo; const AChange: TAtlasFormPropertyChange;
  ACheckOnly: Boolean): string;
var
  mNumber: Integer;
begin
  Result := '';
  mNumber := GetEnumValue(PropTypeOf(AProp), AChange.Value);
  if mNumber < 0 then
  begin
    Result := Format(UiText(TPropertyText.UnknownValue), [AChange.PropertyPath, AChange.Value]);
  end
  else if not ACheckOnly then
  begin
    SetOrdProp(AInstance, AProp, mNumber);
  end;
end;

function AssignSet(AInstance: TObject; AProp: PPropInfo; const AChange: TAtlasFormPropertyChange;
  ACheckOnly: Boolean): string;
var
  mNumber: Integer;
begin
  Result := '';
  try
    mNumber := StringToSet(AProp, AChange.Value);
  except
    // Delphi meldet ein unbekanntes Element als EPropertyConvertError, FPC als EPropertyError.
    on E: Exception do
    begin
      if not (E is EPropertyConvertError) and not (E is EPropertyError) then
      begin
        raise;
      end;
      Exit(Format(UiText(TPropertyText.UnknownSetElement), [AChange.PropertyPath, AChange.Value]));
    end;
  end;
  if not ACheckOnly then
  begin
    SetOrdProp(AInstance, AProp, mNumber);
  end;
end;

function AssignFloat(AInstance: TObject; AProp: PPropInfo; const AChange: TAtlasFormPropertyChange;
  ACheckOnly: Boolean): string;
var
  mFloat: Double;
begin
  Result := '';
  if not TryStrToFloat(AChange.Value, mFloat, TFormatSettings.Invariant) then
  begin
    Result := Format(UiText(TPropertyText.IsNotANumber), [AChange.PropertyPath, AChange.Value]);
  end
  else if not ACheckOnly then
  begin
    SetFloatProp(AInstance, AProp, mFloat);
  end;
end;

{ TAtlasFormPropertyValues }

class function TAtlasFormPropertyValues.ComponentOf(ARoot: TComponent; const AName: string): TComponent;
begin
  Result := ARoot;
  if AName <> '' then
  begin
    Result := ARoot.FindComponent(AName);
  end;
end;

class function TAtlasFormPropertyValues.ComponentMissing(const AName: string): string;
begin
  Result := Format(UiText(TPropertyText.ComponentNotFound), [AName]);
end;

class function TAtlasFormPropertyValues.Resolve(AComponent: TObject; const APath: string; out AInstance: TObject;
  out AProp: PPropInfo): string;
var
  mParts: TArray<string>;
  mIndex: Integer;
begin
  AInstance := AComponent;
  AProp := nil;
  mParts := APath.Split(['.']);
  if Length(mParts) = 0 then
  begin
    Exit(UiText(TPropertyText.NoProperty));
  end;
  for mIndex := 0 to High(mParts) - 1 do
  begin
    AProp := GetPropInfo(AInstance, mParts[mIndex]);
    if (AProp = nil) or (PropTypeOf(AProp)^.Kind <> tkClass) then
    begin
      Exit(Format(UiText(TPropertyText.IsNotAnObjectProperty), [mParts[mIndex]]));
    end;
    AInstance := GetObjectProp(AInstance, AProp);
    if AInstance = nil then
    begin
      Exit(Format(UiText(TPropertyText.IsNotSet), [mParts[mIndex]]));
    end;
  end;
  AProp := GetPropInfo(AInstance, mParts[High(mParts)]);
  if (AProp = nil) or (AProp^.SetProc = nil) then
  begin
    Exit(Format(UiText(TPropertyText.CannotBeSet), [APath]));
  end;
  Result := '';
end;

class function TAtlasFormPropertyValues.WriteValue(AInstance: TObject; AProp: PPropInfo;
  const AChange: TAtlasFormPropertyChange; ACheckOnly: Boolean): string;
begin
  if AChange.Removed then
  begin
    Exit(ResetValue(AInstance, AProp, AChange.PropertyPath, ACheckOnly));
  end;
  case PropTypeOf(AProp)^.Kind of
    tkString, tkLString, tkWString, tkUString:
      Result := AssignString(AInstance, AProp, AChange, ACheckOnly);
    tkInteger:
      Result := AssignInteger(AInstance, AProp, AChange, ACheckOnly);
    tkInt64:
      Result := AssignInt64(AInstance, AProp, AChange, ACheckOnly);
    tkEnumeration:
      Result := AssignEnumeration(AInstance, AProp, AChange, ACheckOnly);
    tkSet:
      Result := AssignSet(AInstance, AProp, AChange, ACheckOnly);
    tkFloat:
      Result := AssignFloat(AInstance, AProp, AChange, ACheckOnly);
  else
    Result := Format(UiText(TPropertyText.TypeIsNotSetIn), [AChange.PropertyPath]);
  end;
end;

class function TAtlasFormPropertyValues.Check(ARoot: TComponent; const AProperties: TArray<TAtlasFormPropertyChange>;
  out ATargets: TArray<TObject>; out AProps: TArray<PPropInfo>): string;
var
  mProp: TAtlasFormPropertyChange;
  mComponent: TComponent;
  mInstance: TObject;
  mPropInfo: PPropInfo;
  mReason: string;
begin
  ATargets := nil;
  AProps := nil;
  for mProp in AProperties do
  begin
    mComponent := ComponentOf(ARoot, mProp.Component);
    if mComponent = nil then
    begin
      Exit(ComponentMissing(mProp.Component));
    end;
    mReason := Resolve(mComponent, mProp.PropertyPath, mInstance, mPropInfo);
    if mReason = '' then
    begin
      mReason := WriteValue(mInstance, mPropInfo, mProp, True);
    end;
    if mReason <> '' then
    begin
      Exit(Format('%s: %s', [mComponent.Name, mReason]));
    end;
    ATargets := ATargets + [mInstance];
    AProps := AProps + [mPropInfo];
  end;
  Result := '';
end;

class procedure TAtlasFormPropertyValues.Apply(const ATargets: TArray<TObject>; const AProps: TArray<PPropInfo>;
  const AProperties: TArray<TAtlasFormPropertyChange>);
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(AProperties) do
  begin
    WriteValue(ATargets[mIndex], AProps[mIndex], AProperties[mIndex], False);
  end;
end;

initialization
  TAtlasTextLanguage.AddTable('Atlas.Core.Forms.PropertyValues', cTexts[TAtlasLanguage.German],
    cTexts[TAtlasLanguage.English]);

end.
