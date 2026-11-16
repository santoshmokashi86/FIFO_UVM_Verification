`timescale 1ns/1ps
package fifo_uvm_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    // Separate analysis implementation types for write and read observations.
    `uvm_analysis_imp_decl(_wr)
    `uvm_analysis_imp_decl(_rd)

    class fifo_item extends uvm_sequence_item;
        rand bit                  wr_en;
        rand bit                  rd_en;
        rand bit [11:0]           wr_data;
             bit [3:0]            rd_data;

        `uvm_object_utils_begin(fifo_item)
            `uvm_field_int(wr_en,   UVM_ALL_ON)
            `uvm_field_int(rd_en,   UVM_ALL_ON)
            `uvm_field_int(wr_data, UVM_ALL_ON)
            `uvm_field_int(rd_data, UVM_ALL_ON)
        `uvm_object_utils_end

        function new(string name = "fifo_item");
            super.new(name);
        endfunction
    endclass

    class fifo_sequencer extends uvm_sequencer #(fifo_item);
        `uvm_component_utils(fifo_sequencer)
        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction
    endclass

    class fifo_sequence extends uvm_sequence #(fifo_item);
        `uvm_object_utils(fifo_sequence)
        function new(string name = "fifo_sequence");
            super.new(name);
        endfunction

        task automatic send_cycle(bit w, bit r, bit [11:0] d);
            fifo_item tr;
            tr = fifo_item::type_id::create("tr");
            start_item(tr);
            tr.wr_en   = w;
            tr.rd_en   = r;
            tr.wr_data = d;
            finish_item(tr);
        endtask

        task body();
            bit [11:0] d;
            int i;

            `uvm_info("SEQ", "Starting directed FIFO fill/drain", UVM_MEDIUM)

            // Fill all 16 word locations.
            for (i = 0; i < 16; i++) begin
                d = $urandom;
                send_cycle(1'b1, 1'b0, d);
            end

            // Attempt one extra write while full; the DUT must reject it.
            send_cycle(1'b1, 1'b0, 12'hBAD);

            // Read all 16 words: 3 output nibbles per word.
            for (i = 0; i < 48; i++)
                send_cycle(1'b0, 1'b1, '0);

            // Attempt one extra read while empty; the DUT must reject it.
            send_cycle(1'b0, 1'b1, '0);

            `uvm_info("SEQ", "Starting concurrent randomized traffic", UVM_MEDIUM)

            // Independent write/read enables are exercised on every item.
            for (i = 0; i < 500; i++) begin
                bit w, r;
                w = ($urandom_range(0,99) < 65);
                r = ($urandom_range(0,99) < 65);
                d = $urandom;
                send_cycle(w, r, d);
            end

            // Drain any words left by random traffic. Extra reads while empty
            // are intentional and must not change the output data.
            for (i = 0; i < 48; i++)
                send_cycle(1'b0, 1'b1, '0);

            `uvm_info("SEQ", "FIFO sequence completed", UVM_MEDIUM)
        endtask
    endclass

    class fifo_driver extends uvm_driver #(fifo_item);
        `uvm_component_utils(fifo_driver)
        virtual fifo_if vif;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(virtual fifo_if)::get(this, "", "vif", vif))
                `uvm_fatal("NOVIF", "fifo_if virtual interface was not configured")
        endfunction

        task drive_write(bit en, bit [11:0] data);
            @(negedge vif.wr_clk);
            vif.wr_en   = en;
            vif.wr_data = data;
            @(negedge vif.wr_clk);
            vif.wr_en = 1'b0;
        endtask

        task drive_read(bit en);
            @(negedge vif.rd_clk);
            vif.rd_en = en;
            @(negedge vif.rd_clk);
            vif.rd_en = 1'b0;
        endtask

        task run_phase(uvm_phase phase);
            fifo_item req;
            vif.wr_en   = 1'b0;
            vif.rd_en   = 1'b0;
            vif.wr_data = '0;
            forever begin
                seq_item_port.get_next_item(req);
                fork
                    drive_write(req.wr_en, req.wr_data);
                    drive_read(req.rd_en);
                join
                seq_item_port.item_done();
            end
        endtask
    endclass

    class fifo_monitor extends uvm_component;
        `uvm_component_utils(fifo_monitor)
        virtual fifo_if vif;
        uvm_analysis_port #(fifo_item) wr_ap;
        uvm_analysis_port #(fifo_item) rd_ap;

        function new(string name, uvm_component parent);
            super.new(name, parent);
            wr_ap = new("wr_ap", this);
            rd_ap = new("rd_ap", this);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(virtual fifo_if)::get(this, "", "vif", vif))
                `uvm_fatal("NOVIF", "fifo_if virtual interface was not configured")
        endfunction

        task run_phase(uvm_phase phase);
            fork
                // Record only writes actually accepted by the DUT.
                forever begin
                    @(posedge vif.wr_clk);
                    if (vif.wr_rst_n && vif.wr_en && !vif.wr_full) begin
                        fifo_item t;
                        t = fifo_item::type_id::create("wr_observation");
                        t.wr_data = vif.wr_data;
                        wr_ap.write(t);
                    end
                end

                // Sample registered read data just after the read clock edge.
                forever begin
                    @(posedge vif.rd_clk);
                    if (vif.rd_rst_n && vif.rd_en && !vif.rd_empty) begin
                        fifo_item t;
                        #1step;
                        t = fifo_item::type_id::create("rd_observation");
                        t.rd_data = vif.rd_data;
                        rd_ap.write(t);
                    end
                end
            join
        endtask
    endclass

    class fifo_scoreboard extends uvm_component;
        `uvm_component_utils(fifo_scoreboard)
        uvm_analysis_imp_wr #(fifo_item, fifo_scoreboard) wr_imp;
        uvm_analysis_imp_rd #(fifo_item, fifo_scoreboard) rd_imp;
        bit [3:0] expected_q[$];
        int unsigned write_words;
        int unsigned read_chunks;
        int unsigned errors;

        function new(string name, uvm_component parent);
            super.new(name, parent);
            wr_imp = new("wr_imp", this);
            rd_imp = new("rd_imp", this);
            write_words = 0;
            read_chunks = 0;
            errors = 0;
        endfunction

        // Every accepted 12-bit write contributes three expected 4-bit reads.
        function void write_wr(fifo_item t);
            expected_q.push_back(t.wr_data[11:8]);
            expected_q.push_back(t.wr_data[7:4]);
            expected_q.push_back(t.wr_data[3:0]);
            write_words++;
        endfunction

        function void write_rd(fifo_item t);
            bit [3:0] exp;
            read_chunks++;
            if (expected_q.size() == 0) begin
                errors++;
                `uvm_error("SCOREBOARD", $sformatf(
                    "Read observed with no expected nibble; got=%h", t.rd_data))
            end else begin
                exp = expected_q.pop_front();
                if (t.rd_data !== exp) begin
                    errors++;
                    `uvm_error("DATA_MISMATCH", $sformatf(
                        "Read chunk %0d: expected=%h actual=%h",
                        read_chunks, exp, t.rd_data))
                end
            end
        endfunction

        function void check_phase(uvm_phase phase);
            super.check_phase(phase);
            if (expected_q.size() != 0)
                `uvm_error("SCOREBOARD", $sformatf(
                    "%0d expected output chunks were not read", expected_q.size()))
            `uvm_info("SCOREBOARD", $sformatf(
                "Accepted write words=%0d, accepted read chunks=%0d, remaining expected=%0d, data errors=%0d",
                write_words, read_chunks, expected_q.size(), errors), UVM_LOW)
        endfunction
    endclass

    class fifo_agent extends uvm_agent;
        `uvm_component_utils(fifo_agent)
        fifo_sequencer seqr;
        fifo_driver    drv;
        fifo_monitor   mon;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            seqr = fifo_sequencer::type_id::create("seqr", this);
            drv  = fifo_driver::type_id::create("drv", this);
            mon  = fifo_monitor::type_id::create("mon", this);
        endfunction

        function void connect_phase(uvm_phase phase);
            super.connect_phase(phase);
            drv.seq_item_port.connect(seqr.seq_item_export);
        endfunction
    endclass

    class fifo_env extends uvm_env;
        `uvm_component_utils(fifo_env)
        fifo_agent      agent;
        fifo_scoreboard sb;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            agent = fifo_agent::type_id::create("agent", this);
            sb    = fifo_scoreboard::type_id::create("sb", this);
        endfunction

        function void connect_phase(uvm_phase phase);
            super.connect_phase(phase);
            agent.mon.wr_ap.connect(sb.wr_imp);
            agent.mon.rd_ap.connect(sb.rd_imp);
        endfunction
    endclass

    class fifo_test extends uvm_test;
        `uvm_component_utils(fifo_test)
        fifo_env env;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            env = fifo_env::type_id::create("env", this);
        endfunction

        task run_phase(uvm_phase phase);
            fifo_sequence seq;
            phase.raise_objection(this);
            seq = fifo_sequence::type_id::create("seq");
            seq.start(env.agent.seqr);
            // Allow the final synchronizer and monitor activity to settle.
            repeat (5) @(posedge env.agent.drv.vif.rd_clk);
            phase.drop_objection(this);
        endtask
    endclass

endpackage
