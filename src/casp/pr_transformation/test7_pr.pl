pr_rule(p,[not(q)]).
pr_rule(q,[not(p)]).
pr_rule(r,[not(s),q]).
pr_rule(s,[not(r)]).
pr_rule(not(o_s1),[r]).
pr_rule(not(s),[not(o_s1)]).
pr_rule(not(o_r1),[s]).
pr_rule(not(o_r1),[not(s),not(q)]).
pr_rule(not(r),[not(o_r1)]).
pr_rule(not(o_q1),[p]).
pr_rule(not(q),[not(o_q1)]).
pr_rule(not(o_p1),[q]).
pr_rule(not(p),[not(o_p1)]).
pr_rule(not(o__false1),[r]).
pr_rule(not(o_false),[not(o__false1)]).
pr_rule(not(o__chk11),[r]).
pr_rule(not(o_chk1),[not(o__chk11)]).
pr_rule(not(o_false),[]).
pr_rule(o_nmr_check,[not(o_chk1)]).
pr_rule(add_to_query,[o_nmr_check]).