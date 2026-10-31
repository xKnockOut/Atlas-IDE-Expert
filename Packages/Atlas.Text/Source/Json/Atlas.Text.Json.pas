unit Atlas.Text.Json;

// JSON-Strings von Hand schreiben (gemeinsam für Server und Plugin, ADR 0012):
// Anführungszeichen, Backslash und Steuerzeichen wie RFC 8259 maskieren, alle
// übrigen Zeichen unverändert (auch Umlaute, anders als TJSONValue.ToJSON).
// Ausgaben, die den Text selbst zusammensetzen (Linter-Befunde, Baseline,
// Metriken), teilen sich diese eine Regel (#1450).

interface

uses
  System.SysUtils;

type
  TJsonText = class
  public
    /// <summary>AText als JSON-String samt Anführungszeichen.</summary>
    class function Quote(const AText: string): string; static;
  end;

implementation

{ TJsonText }

class function TJsonText.Quote(const AText: string): string;
var
  mBuilder: TStringBuilder;
  mChar: Char;
begin
  mBuilder := TStringBuilder.Create;
  try
    mBuilder.Append('"');
    for mChar in AText do
      case mChar of
        '"':
          mBuilder.Append('\"');
        '\':
          mBuilder.Append('\\');
        #8:
          mBuilder.Append('\b');
        #9:
          mBuilder.Append('\t');
        #10:
          mBuilder.Append('\n');
        #12:
          mBuilder.Append('\f');
        #13:
          mBuilder.Append('\r');
      else
        if Ord(mChar) < 32 then
          mBuilder.Append('\u' + IntToHex(Ord(mChar), 4))
        else
          mBuilder.Append(mChar);
      end;
    mBuilder.Append('"');
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

end.
