/*
   Copyright (C) 2010 bg <bg_one@mail.ru>
*/
#ifndef CHAN_DONGLE_CHANNEL_H_INCLUDED
#define CHAN_DONGLE_CHANNEL_H_INCLUDED

#include <asterisk.h>
#include <asterisk/frame.h>		/* enum ast_control_frame_type */
#include <asterisk/channel.h>		/* struct ast_assigned_ids */

#include "export.h"			/* EXPORT_DECL EXPORT_DEF */
#include "cpvt.h"			/* call_state_t */


typedef struct channel_var
{
	const char	* name;
	char		* value;
} channel_var_t;

struct pvt;

EXPORT_DECL struct ast_channel_tech channel_tech;

EXPORT_DECL struct ast_channel* new_channel (struct pvt * pvt, int ast_state, const char * cid_num, int call_idx, unsigned dir, call_state_t state, const char * exten, const struct ast_assigned_ids *assignedids, const struct ast_channel * requestor);
EXPORT_DECL int queue_control_channel (struct cpvt * cpvt, enum ast_control_frame_type control);
EXPORT_DECL int queue_hangup (struct ast_channel * channel, int hangupcause);
EXPORT_DECL void start_local_channel (struct pvt * pvt, const char * exten, const char * number, channel_var_t * vars);
EXPORT_DECL void change_channel_state(struct cpvt * cpvt, unsigned newstate, int cause);
EXPORT_DECL int channels_loop(struct pvt * pvt, const struct ast_channel * requestor);
EXPORT_DECL int channel_tech_caps_initialize(void);
EXPORT_DECL void channel_tech_caps_destroy(void);
EXPORT_DECL struct ast_format_cap *channel_tech_caps_get(void);


#endif /* CHAN_DONGLE_CHANNEL_H_INCLUDED */
