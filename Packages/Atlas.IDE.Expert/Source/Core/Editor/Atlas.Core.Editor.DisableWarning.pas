unit Atlas.Core.Editor.DisableWarning;

// Argumente der Client-Befehle „Warnung abschalten“ (#531), ohne IDE:
//   - atlas.disableWarning [uri, Zeile, Nummer, Bereich, fragen]: Das Plugin
//     fragt bei „fragen“ nach einer Begründung und ruft
//     atlas.server.disableWarning [uri, Zeile, Nummer, Bereich, Begründung].
//   - atlas.disableWarningProject [uri, Nummer, Bezeichner]: Das Plugin trägt
//     nach Rückfrage DCC_<Bezeichner> = false in die Basiskonfiguration des
//     Projekts ein (so speichert die IDE die Warnungen der Compiler-Optionen).

interface

uses
  System.SysUtils;

type
  TAtlasDisableWarningRequest = record
    Uri: string;
    Line: Integer;
    Code: string;
    Scope: string;
    AskReason: Boolean;
    /// <summary>Liest die Argumente von atlas.disableWarning; False bei unvollständigen.</summary>
    class function TryParse(const AArgumentsJson: string; out ARequest: TAtlasDisableWarningRequest): Boolean;
      static;
    /// <summary>Argumente für atlas.server.disableWarning mit der Begründung AReason.</summary>
    function ApplyArguments(const AReason: string): string;
  end;

  TAtlasDisableWarningProject = record
    Uri: string;
    Code: string;
    Identifier: string;
    /// <summary>Liest die Argumente von atlas.disableWarningProject; False ohne gültigen Bezeichner.</summary>
    class function TryParse(const AArgumentsJson: string; out ARequest: TAtlasDisableWarningProject): Boolean;
      static;
    /// <summary>Name der Projektoption, z. B. DCC_SYMBOL_DEPRECATED.</summary>
    function OptionName: string;
  end;

const
  /// <summary>Wert der Projektoption für „Warnung aus“.</summary>
  AtlasWarningOptionOff = 'false';

implementation

uses
  System.JSON;

function ArgumentsOf(const AJson: string): TJSONArray;
var
  Value: TJSONValue;
begin
  Result := nil;
  Value := TJSONObject.ParseJSONValue(AJson);
  if Value is TJSONArray then
    Result := TJSONArray(Value)
  else
    Value.Free;
end;

function IsIdentifier(const AText: string): Boolean;
var
  Index: Integer;
begin
  Result := AText <> '';
  for Index := 1 to Length(AText) do
    if not CharInSet(AText[Index], ['A'..'Z', '0'..'9', '_']) then
      Exit(False);
end;

{ TAtlasDisableWarningRequest }

class function TAtlasDisableWarningRequest.TryParse(const AArgumentsJson: string;
  out ARequest: TAtlasDisableWarningRequest): Boolean;
var
  Arguments: TJSONArray;
begin
  ARequest := Default(TAtlasDisableWarningRequest);
  Arguments := ArgumentsOf(AArgumentsJson);
  try
    Result := (Arguments <> nil) and (Arguments.Count >= 4);
    if not Result then
      Exit;
    ARequest.Uri := Arguments.Items[0].Value;
    ARequest.Line := StrToIntDef(Arguments.Items[1].Value, -1);
    ARequest.Code := Arguments.Items[2].Value;
    ARequest.Scope := Arguments.Items[3].Value;
    ARequest.AskReason := (Arguments.Count > 4) and (Arguments.Items[4] is TJSONBool) and
      TJSONBool(Arguments.Items[4]).AsBoolean;
    Result := (ARequest.Uri <> '') and (ARequest.Line >= 0) and (ARequest.Code <> '') and (ARequest.Scope <> '');
  finally
    Arguments.Free;
  end;
end;

function TAtlasDisableWarningRequest.ApplyArguments(const AReason: string): string;
var
  Arguments: TJSONArray;
begin
  Arguments := TJSONArray.Create;
  try
    Arguments.Add(Uri);
    Arguments.AddElement(TJSONNumber.Create(Line));
    Arguments.Add(Code);
    Arguments.Add(Scope);
    Arguments.Add(Trim(AReason));
    Result := Arguments.ToJSON;
  finally
    Arguments.Free;
  end;
end;

{ TAtlasDisableWarningProject }

class function TAtlasDisableWarningProject.TryParse(const AArgumentsJson: string;
  out ARequest: TAtlasDisableWarningProject): Boolean;
var
  Arguments: TJSONArray;
begin
  ARequest := Default(TAtlasDisableWarningProject);
  Arguments := ArgumentsOf(AArgumentsJson);
  try
    Result := (Arguments <> nil) and (Arguments.Count >= 3);
    if not Result then
      Exit;
    ARequest.Uri := Arguments.Items[0].Value;
    ARequest.Code := Arguments.Items[1].Value;
    ARequest.Identifier := UpperCase(Trim(Arguments.Items[2].Value));
    // Nur Bezeichner wie SYMBOL_DEPRECATED: Der Name wird Teil einer Projektoption.
    Result := (ARequest.Uri <> '') and IsIdentifier(ARequest.Identifier);
  finally
    Arguments.Free;
  end;
end;

function TAtlasDisableWarningProject.OptionName: string;
begin
  Result := 'DCC_' + Identifier;
end;

end.
