unit Atlas.Tests.RecordText;

// Testhilfe (#2197): Records als Text für Assert.AreEqual. AreEqual<T> vergleicht Records binär statt mit
// ihrem =, und die Meldung beim Fehlschlag zeigt nur "(record)"; als Text nennt sie erwartet und erhalten.

interface

uses
  System.Types,
  Atlas.Text.Lines;

type
  TRecordText = record
  public
    /// <summary>"Zeile:Zeichen", beide 0-basiert.</summary>
    class function Position(const APosition: TTextPosition): string; overload; static;
    /// <summary>Wie Position(TTextPosition.Create(ALine, ACharacter)).</summary>
    class function Position(ALine, ACharacter: Integer): string; overload; static;
    /// <summary>"(Left,Top)-(Right,Bottom)".</summary>
    class function Rect(const ARect: TRect): string; static;
    /// <summary>Werte durch Komma getrennt, z. B. "0,1".</summary>
    class function Ints(const AValues: TArray<Integer>): string; static;
  end;

implementation

uses
  System.SysUtils;

{ TRecordText }

class function TRecordText.Position(const APosition: TTextPosition): string;
begin
  Result := Position(APosition.Line, APosition.Character);
end;

class function TRecordText.Position(ALine, ACharacter: Integer): string;
begin
  Result := Format('%d:%d', [ALine, ACharacter]);
end;

class function TRecordText.Rect(const ARect: TRect): string;
begin
  Result := Format('(%d,%d)-(%d,%d)', [ARect.Left, ARect.Top, ARect.Right, ARect.Bottom]);
end;

class function TRecordText.Ints(const AValues: TArray<Integer>): string;
var
  mValue: Integer;
begin
  Result := '';
  for mValue in AValues do
  begin
    if Result <> '' then
    begin
      Result := Result + ',';
    end;
    Result := Result + IntToStr(mValue);
  end;
end;

end.
