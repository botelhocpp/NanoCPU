---------------------------------------------------------------------------
-- Fernando Moraes - 04/nov/2024  - -- NanoCPU para FSD
-- Cesar Marcon    - 12/nov/2024  
---------------------------------------------------------------------------

--++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
-- 16-bit register  with we (enable writing into the register)
--++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
library IEEE;
use IEEE.std_logic_1164.all;

entity Reg16bit is
	port
	(
		ck, rst, we: in std_logic;
		D: in  std_logic_vector(15 downto 0);
		Q: out std_logic_vector(15 downto 0)
	);
end Reg16bit;

architecture Reg16b of Reg16bit is
begin
	process(ck, rst)
	begin
		if rst = '1' then
			Q <= (others=>'0');
		elsif ck'event and ck = '1' then
			if we = '1' then
				Q <= D;
			end if;
		end if;
	end process;
end Reg16b;

--++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
-- NanoCPU description  
--++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
library IEEE;
use IEEE.Std_Logic_1164.all;
use IEEE.std_logic_unsigned.all;

entity NanoCPU is
	port
	(
		ck, rst: in std_logic;
		address: out std_logic_vector(7 downto 0);
		dataR: in  std_logic_vector(15 downto 0);
		dataW: out std_logic_vector(15 downto 0);
		ce, we: out std_logic
	);     
end NanoCPU;

architecture NCPU of NanoCPU is

    type instType is (iREAD, iWRITE, iXOR, iSUB, iADD, iLESS, iEND);
    signal inst: instType;   

    type bankType is array(0 to 3) of std_logic_vector(15 downto 0);
    signal reg: bankType;

    signal wPC, wIR, wReg: std_logic;
    signal wen: std_logic_vector(3 downto 0);
    signal addReg: std_logic_vector(1 downto 0);

    signal IR, RS1, RS2, muxRegIn, outalu, muxPC, PC, less: std_logic_vector(15 downto 0);

   type stateType is (sFETCH, sEXE, sREAD, sWRITE, sEND, sALU); --ok
    signal state: stateType;

begin

   --++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
   -- data-path - responsible to execute the current instruction 
   --++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

	-- memory interface
	-- 
	dataW <= outalu;
	address <= PC(7 downto 0) when state = sFETCH else ir(11 downto 4);
	ce <= '1';   -- always reading
	we <= '1' when state = sWRITE else '0';   -- write in the store
   
	-- register bank - 4 general purpose registers
	-- 
	r0 : entity work.Reg16bit port map(ck => ck, rst => rst, we => wen(0), D => muxRegIn, Q => reg(0));
	r1 : entity work.Reg16bit port map(ck => ck, rst => rst, we => wen(1), D => muxRegIn, Q => reg(1));
	r2 : entity work.Reg16bit port map(ck => ck, rst => rst, we => wen(2), D => muxRegIn, Q => reg(2));
	r3 : entity work.Reg16bit port map(ck => ck, rst => rst, we => wen(3), D => muxRegIn, Q => reg(3));
   --ok

	wen(0) <= '1' when addReg = "00" and wReg = '1' else '0';
	wen(1) <= '1' when addReg = "01" and wReg = '1' else '0';
 	wen(2) <= '1'when addReg = "10" and wReg = '1' else '0'; 
	wen(3) <= '1' when addReg = "11" and wReg = '1'else '0'; 
   --ok

	addReg <= IR(1 downto 0) when state = sREAD else IR(9 downto 8);   -- index of the register to write
	muxRegIn <= dataR when state = sREAD else outalu;

	RS1 <= reg(CONV_INTEGER(IR(5 downto 4)));       -- multiplexers to read registers
	RS2 <= reg(CONV_INTEGER(IR(1 downto 0)));   

   -- arithmetic and logic unit 
   -- 
	outalu <=	RS2           when inst = iWRITE else  -- data to be written is the second register
				RS1 xor RS2   when inst = iXOR else 
				RS1 - RS2     when inst = iSUB else  
				less          when inst = iLESS else 
				RS1 + RS2;    --  default operation: iADD

				
				--          when inst = iREAD else 

	less <= x"0001" when RS1 < RS2 else x"0000";

   -- IR and PC registers
   --  
	R_IR: entity work.Reg16bit port map(ck => ck, rst => rst, we => wIR, D => dataR, Q => IR);
	R_PC: entity work.Reg16bit port map(ck => ck, rst => rst, we => wPC, D => muxPC, Q => PC);

	muxPC <=   PC + 1;

   --++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
   -- control block  - manages the execution of instructions
   --++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

	inst <=	iREAD      when ir(15 downto 12) = x"0" else    -- decode the current instruction
			iWRITE     when ir(15 downto 12) = x"1" else
			iXOR       when ir(15 downto 12) = x"4" else
			iSUB       when ir(15 downto 12) = x"5" else
			iADD       when ir(15 downto 12) = x"6" else
			iLESS      when ir(15 downto 12) = x"7" else
			iEND;

	wPC <= '1' when state = sREAD OR state = sWRITE OR state = sALU --complete
		else '0';
	wReg <= '1' when state = sREAD OR state = sALU  --complete
		else '0';
	wIR <= '1' when state = sFETCH else '0';

	process(ck, rst)
	begin
		if rst = '1' then
			state <= sFETCH;
		elsif ck'event and ck = '1' then
			case state is
				when sFETCH =>
					state <= sEXE;
				when sEXE =>
					if inst = iEND then
						state <= sEND;
					elsif inst = iREAD then
						state <= sREAD;
					elsif inst = iWRITE then
						state <= sWRITE;
					else
						state <= sALU;
					end if;
				when sEND =>
					state <= sEND;
				when others =>
					state <= sFETCH;
			end case;
		end if;
	end process;

end NCPU;
